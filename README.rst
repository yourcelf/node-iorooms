IORooms
=======

Super alpha, watch out!

The problem: Socket.IO implements "rooms", but they're based on *sockets*, not
*sessions*.  But browsers can have multiple tabs and windows open, hence
multiple sockets per session.

Express.js implements *sessions*, but using cookies, not sockets.  

IORooms joins the two together simply, so that you can use sockets for data --
but every socket gets a `session` property which refers to the express session
associated with it.  Yay!  Now every socket has a session, and it's the same
session standard HTTP requests through express use.

Based initially on this blogpost: http://www.danielbaulig.de/socket-ioexpress/

Usage example
-------------

Example server::

    express = require('express');
    connect = require('connect'); // use connect v1.x
    RoomManager = require('/iorooms').RoomManager;

    sessionStore = new connect.session.MemoryStore(); // or redis, or ...

    app = express.createServer();
    app.configure(function() {
        app.use(express.cookieParser());
        app.use(express.session({
           secret: "shhh don't tell",
           store: sessionStore,
           key: "express.sid"
        }));
    });

    io = socketio.listen(app);
    iorooms = new RoomManager("/iorooms", io, sessionStore);

    // Respond to a message
    iorooms.onChannel("message", function(socket, data) {
        // `socket.session` contains the session
        // `data` contains the message from the client
    });

On the client::

    socket = io.connect("/iorooms");
    
    // join a room.
    socket.emit("join", {room: "my room"});
    // leave a room
    socket.emit("leave", {room: "my room"});

    socket.on("connect", function() {
        // callbacks pertinent to rooms:
        socket.on("users", function(data) {
            // data is a structure of people in the room, with properties
            // "self" and "others".  Emitted to the client after successfully
            // joining a room.
        });
        socket.on("user_joined", function(data) {
            // data is a structure representing a single user who has just
            // joined.
        });
        socket.on("user_left", function(data) {
            // data is a structure representing a single user who has just
            // left.
        });
    });

See ``testserver.coffee`` and ``views/test.jade``, as well as the behavior tests in ``spec/iorooms.spec.coffee``, for a full client/server example.

RoomManager
-----------

``RoomManager`` is a class for handling the establishment of sockets, and the connection of sockets to express sessions.

Constructor: ``new RoomManager(route, io, store, options)``

* ``route``: A string describing the channel name to use.
* ``io``: A socket.io object.
* ``store``: A session store, such as ``connect.session.MemoryStore`` or the session store from ``redis-connect``.
* ``options``: Only option for now is ``logger``, which is an object which defines ``error`` and ``debug`` logger handles to use.

Authorization
~~~~~~~~~~~~~

If you want to control who can connect to your socket or room, override one or more of the following methods on `RoomManager`.  By default, all requests to establish a socket or join a room are allowed:

* ``authorizeConnection(session, callback)``: Should the user with the given
  ``session`` be allowed to connect to the socket at all?  If so, call
  ``callback(null)``.  Otherwise, call ``callback(error)``, where error is
  non-null.
* ``authorizeJoinRoom(session, name, callback)``: Should the user with the given
  ``session`` be allowed to join the room ``name``?  If so, call ``callback(null)``.
  Otherwise, call ``callback(error)``, where error is non-null.

Example::

    var iorooms = new RoomManager("/iorooms", io, sessionStore)
    iorooms.authorizeConnection = function(session, callback) {
        if (session.is_authenticated) {
            callback(null);
        } else {
            callback("Must authenticate first");
        }
    };

Channel messages
~~~~~~~~~~~~~~~~

Respond to messages within or between rooms with the shortcut ``RoomManager.onChannel(message, callback)``.  For example, responding to the message "my-message"::

    iorooms.onChannel("my-message", function(socket, data) {
        // ... socket.session contains the session
    });

This is equivalent to::

    io.of(routename).on('connection', function(socket) {
        socket.on("my-message", function(data) {
            // ... socket.session contains the session
        });
    });

Tests
-----

Tests are written with ``mocha``.  Run tests using ``mocha --compilers coffee:coffee-script spec/*`` (or via the shortcut ``npm test``).  Since the tests spawn a couple of zombie.js instances and communicate with the server, if you have a slow computer, you may need to increase the timeout, by adding ``--timeout 5000`` or similar to the mocha command.
