#
# Manage rooms with express sessions and socket IO.
#

events      = require 'events'
parseCookie = require('connect').utils.parseCookie
_           = require 'underscore'

class RoomManager extends events.EventEmitter
  constructor: (route, io, store, options) ->
    @socketSessionMap = {}
    @route = route or "/iorooms"
    @io = io
    @store = store

    # Map of room names to a list of session ID's in that room
    @roomSessions = {}
    # Map of session ID's to a list of rooms for that session
    @sessionRooms = {}
    # Map of session ID's to a list of socket ID's for that session
    @sessionSockets = {}

    _.extend this, options

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

  saveSession: (session, callback) =>
    @store.set session.sid, session, callback

  clearSession: (session, callback) =>
    @store.destroy session.sid, callback

  setIOAuthorization: =>
    @io.set "authorization", (handshake, callback) =>
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
      socket.session = socket.handshake.session
      # Join a socket room based on the session ID, so that we can message all
      # sockets for a particular session at once.
      socket.join socket.session.sid
      
      # Establish a list of sockets connected under this session. We need this
      # in order to determine whether a socket leaving/disconnecting
      # constitutes the session leaving/disconnecting.
      unless @sessionSockets[socket.session.sid]?
        @sessionSockets[socket.session.sid] = []
      @sessionSockets[socket.session.sid].push(socket.id)

      socket.on 'join', (data) => @join(socket, data)
      socket.on 'leave', (data) => @leave(socket, data)
      socket.on 'disconnect', (data) => @disconnect(socket)

  onChannel: (message, callback) ->
    @io.of(@route).on 'connection', (socket) ->
      socket.on message, (data) -> callback(socket, data)

  join: (socket, data) =>
    room = data.room
    unless room?
      socket.emit "error", error: "Room not specified"

    @authorizeJoinRoom socket.session, room, (err) =>
      if err? then return socket.emit "error", error: err
      socket.join room

      if not @roomSessions[room]?
        @roomSessions[room] = []
      if not @sessionRooms[socket.session.sid]
        @sessionRooms[socket.session.sid] = []

      first = not _.contains @roomSessions[room], socket.session.sid
      if first
        @roomSessions[room].push(socket.session.sid)
        @sessionRooms[socket.session.sid].push(room)

      @emit "join", {
        socket: socket
        room: room
        first: first
      }

  leave: (socket, data) =>
    room = data.room
    unless room?
      socket.emit "error", error: "Room not specified"
      return
    socket.leave(room)

    # See if this session has another socket connected to this room.
    # Get the list of socket IDs connected to a room (list maintained by socket.io).
    roomClients = @io.rooms["#{@route}/#{room}"]
    otherSocketFound = false
    if roomClients? and @sessionSockets[socket.session.sid]?
      # Iterate over all the sockets connected to this session, to see if those
      # sockets are in this room.
      for socketID in @sessionSockets[socket.session.sid]
        if _.contains roomClients, socketID
          otherSocketFound = true
          break

    if not otherSocketFound
      # Remove this session from the room.
      sid = socket.session.sid
      @roomSessions[room] = _.reject @roomSessions[room], (s) -> s == sid
      @sessionRooms[sid] = _.reject @sessionRooms[sid], (r) -> r == room

    @emit "leave", {
      socket: socket
      room: room
      last: not otherSocketFound
    }

  disconnect: (socket) =>
    # Disconnect the socket. Leave any rooms that the socket is in.
    sessid = socket.session.sid
    @sessionSockets[sessid] = _.reject @sessionSockets[sessid], (sockid) -> sockid == socket.id
    if @sessionSockets[sessid].length == 0
      delete @sessionSockets[sessid]
    if @io.roomClients[socket.id]?
      for routeroom, connected of @io.roomClients[socket.id]
        # chomp off the route part to get the room name.
        room = routeroom.substring(@route.length + 1)
        if room and @roomSessions[room]?
          @leave(socket, {room: room})
    socket.leave socket.session.sid

  getSessionsInRoom: (room, cb) =>
    if not @roomSessions[room]?.length
      return cb(null, [])
    sessions = []
    errors = []
    count = @roomSessions[room].length
    for sid in @roomSessions[room]
      do (sid) =>
        @store.get sid, (err, result) ->
          if err?
            errors.push(err)
          else
            sessions.push(result)
          count -= 1
          if count == 0
            if errors.length == 0
              cb(null, sessions)
            else
              cb(errors, null)

module.exports = { RoomManager }
