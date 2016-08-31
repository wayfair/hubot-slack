{RtmClient, WebClient, MemoryDataStore} = require '@slack/client'
SlackFormatter = require './formatter'
_ = require 'lodash'

SLACK_CLIENT_OPTIONS =
  dataStore: new MemoryDataStore()


class SlackClient

  constructor: (options) ->
    _.merge SLACK_CLIENT_OPTIONS, options

    # RTM is the default communication client
    @rtm = new RtmClient options.token, options

    # Web is the fallback for complex messages
    @web = new WebClient options.token, options

    # Message formatter
    @format = new SlackFormatter(@rtm.dataStore)

    # Track listeners for easy clean-up
    @listeners = []


  ###
  Open connection to the Slack RTM API
  ###
  connect: ->
    @rtm.login()


  ###
  Slack RTM event delegates
  ###
  on: (name, callback) ->
    @listeners.push(name)

    # override message to format text
    if name is "message"
      @rtm.on name, (message) =>
        {user, channel, bot_id} = message

        message.text = @format.incoming(message)
        message.user = @rtm.dataStore.getUserById(user) if user
        message.bot = @rtm.dataStore.getBotById(bot_id) if bot_id
        message.channel = @rtm.dataStore.getChannelGroupOrDMById(channel) if channel
        callback(message)

    else
      @rtm.on(name, callback)


  ###
  Disconnect from the Slack RTM API and remove all listeners
  ###
  disconnect: ->
    @rtm.removeListener(name) for name in @listeners
    @listeners = [] # reset


  ###
  Set a channel's topic
  ###
  setTopic: (envelope, topic) ->
    room = envelope.room
    if !(room.match /[A-Z]/) # slack rooms are always lowercase
      # try to translate room name to room id
      channelForName = @rtm.dataStore.getChannelByName(room)
      if channelForName
        room = channelForName.id
    @web.channels.setTopic(room, topic)


  ###
  Send a message to Slack using the best client for the message type
  ###
  send: (envelope, message) ->
    message = @format.outgoing(message)
    room = envelope.room
    if !(room.match /[A-Z]/) # slack rooms are always lowercase
      # try to translate room name to channel/group/DM ID
      channelForName = @rtm.dataStore.getChannelOrGroupByName(room) or @rtm.dataStore.getDMByName(room)

      if channelForName
        room = channelForName.id
      else
        # If we can't find a valid channel/group/DM for the room input, treat it as a username and try
        # to start a direct message. This resolves cases where hubot can't DM a user if no previous DM
        # exists between the two.
        userForName = @rtm.dataStore.getUserByName(room)
        if userForName
          @web.im.open userForName.id, (err, resp) =>
            # try to send the message again only if we successfully opened a DM
            if (not err) and resp.ok
              @send envelope, message
          return

    if typeof message isnt 'string'
      @web.chat.postMessage(room, message.text, _.defaults(message, {'as_user': true}))
    else if /<.+\|.+>/.test(message)
      @web.chat.postMessage(room, message, {'as_user' : true})
    else
      @rtm.sendMessage(message, room) # RTM behaves as though `as_user` is true already


module.exports = SlackClient
