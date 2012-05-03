#
# Manage rooms with express sessions and socket IO.
#

events      = require 'events'
parseCookie = require('connect').utils.parseCookie
_           = require 'underscore'

class RoomManager
  logger:
    debug: (->)
    error: (->)

  constructor: (route, io, store, options) ->
    @socketSessionMap = {}
    @route = route or "/iorooms"
    @io = io
    @store = store
    if options?.logger?
      @logger = options.logger

    @setIOAuthorization()
    @setIOConnection()
  
  authorizeConnection: (session, callback) =>
    # Use this function to determine whether or not a session can connect to
    # the socket.  If not, call the callback with a truthy value (probably an
    # error message) as the first argument.
    #
    # Could also be used to set properties for a new session like a userID.
    callback(null)

  authorizeJoinRoom: (session, room, callback) =>
    # Use this function to determine whether or not a session can connect to
    # the room.  If not, call the callback with a truthy value (probably an
    # error message) as the first argument.
    callback(null)

  authorizeUsername: (session, name, callback) =>
    # Use this function to determine whether or not a session can set its
    # username to the specified name.  If not, call the callback with a truthy
    # value (probably an error message) as the first argument.
    callback(null)

  saveSession: (session, callback) =>
    @store.set session.sid, session, (err) =>
      if err? then @logger.error "Error storing session"
      callback?(err)

  setIOAuthorization: =>
    @io.set "authorization", (handshake, callback) =>
      @logger.debug "Handshake"
      unless handshake.headers.cookie
        callback("Cookie missing.", false)
      else
        cookie = parseCookie(handshake.headers.cookie)
        sessionID = cookie['express.sid']
        @store.get sessionID, (err, session) =>
          if err? or not session
            callback(err?.message or "Error acquiring session", false)
          else
            handshake.session = session
            handshake.session.sid = sessionID
            @authorizeConnection session, (err) =>
              if err? then return callback(err, false)
              @saveSession session, (err) =>
                if err?
                  callback(err, false)
                else
                  callback(null, true)

  setIOConnection: =>
    @io.of(@route).on 'connection', (socket) =>
      @logger.debug("Connection")
      # Map socket ID to session on connection.  There may be multiple sockets
      # per session, if one has multiple tabs/windows open.
      socket.session = socket.handshake.session
      @socketSessionMap[socket.id] = socket.session
      @bindRoomEvents(socket)

  on: (message, callback) ->
    @io.of(@route).on 'connection', (socket) ->
      socket.on message, (data) -> callback(socket, data)

  bindRoomEvents: (socket) =>
    # Room events
    socket.on 'join', (data) => @join(data, socket)
    socket.on 'leave', (data) => @leave(data, socket)
    socket.on 'disconnect', (data) => @disconnect(data, socket)
    socket.on 'username', (data) => @username(data, socket)

  join: (data, socket) =>
    # Request to join a room.  Expects a data payload of the form:
    # {
    #   room: <room name>
    # }
    @logger.debug "join", data
    unless data.room? and socket.session?
      socket.emit "error", error: "Room not specified or session not found."
      return
    @authorizeJoinRoom socket.session, data.room, (err) =>
      if err? then return socket.emit "error", error: err
      unless socket.session.rooms?
        socket.session.rooms = []
      unless _.contains socket.session.rooms, data.room
        socket.session.rooms.push(data.room)
        @saveSession(socket.session)
      socket.join data.room
      @broadcastJoined(data, socket)

  broadcastJoined: (data, socket) =>
    users = @getUsers(data.room, socket)
    socket.emit 'users', users
    unless users.others[socket.session.user_id]
      socket.broadcast.to(data.room).emit 'user_joined', users.self

  leave: (data, socket) =>
    # Request to leave a room.  Expects a data payload of the form:
    # {
    #   room: <room name>
    # }
    @logger.debug "leave", data
    unless data.room? and socket.session?
      socket.emit "error", error: "Room not specified or sessionID not found"
      return
    socket.leave(data.room)
    socket.session.rooms = _.reject socket.session.rooms, (a) -> a == data.room
    @saveSession(socket.session)
    users = @getUsers(data.room, socket)
    # Broadcast that we've left, if we have no other connected sockets.
    unless users.others[socket.session.user_id]
      @broadcastLeft(data, socket)

  broadcastLeft: (data, socket) =>
    socket.broadcast.to(data.room).emit 'user_left',
      user_id: socket.session.user_id
      name: socket.session.name

  username: (data, socket) =>
    # Request to set a username.  Expects a data payload of the form:
    # {
    #   name: <user name>
    # }
    unless data.name? and socket.session?
      socket.emit "error", error: "Name not specified or sessionID not found"
      return
    @authorizeUsername socket.session, data.name, (err) =>
      if (err?)
        socket.emit "error", error: err
      else
        socket.session.name = data.name
        @saveSession socket.session, (err) =>
          @broadcastUsername(data, socket) unless err?

  broadcastUsername: (data, socket) =>
    socket.broadcast.to(socket.room).emit 'username', {
      user_id: socket.session.user_id
      name: data.name
    }

  disconnect: (data, socket) =>
    # Disconnect the socket. Leave any rooms that the socket is in.
    #
    @logger.debug "disconnect", socket.id
    for room, connected of @io.roomClients[socket.id]
      # chomp off the route part to get the room name.
      room = room.substring(@route.length + 1)
      if room then @leave {room: room}, socket
    delete @socketSessionMap[socket.id]

  getUsers: (room, socket) ->
    # Return the users of a room, and yourself, in the following format:
    # {
    #   others: {user_id: <string>, name: <string>}
    #   self: {user_id: <string>, name: <string>}
    # }
    users = {others: {}}
    socketIDs = @io.rooms[[@route, room].join("/")]
    unless socketIDs?
      return users
    
    # eliminate duplicate sockets (e.g. multiple tabs in same room)
    uniqueIDs = {}
    selfSession = null
    for id in socketIDs
      if id == socket?.id
        selfSession = @socketSessionMap[id]
      else
        uniqueIDs[@socketSessionMap[id].sid] = @socketSessionMap[id]
    if selfSession?
      users.self =
        user_id: selfSession.user_id
        name: selfSession.name
    for sessionID, session of uniqueIDs
      users.others[session.user_id] =
        user_id: session.user_id
        name: session.name
    return users
  
module.exports = { RoomManager }
