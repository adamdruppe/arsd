/++
	Module for interacting with the Discord chat service. I use it to run a discord bot providing some slash commands.


	$(LIST
		* Real time gateway
			See [DiscordGatewayConnection]

			You can use [SlashCommandHandler] subclasses registered with a gateway connection to easily add slash commands to your app.
		* REST api
			See [DiscordRestApi]
		* Local RPC server
			See [DiscordRpcConnection] (not implemented)
		* Voice connections
			not implemented
		* Login with Discord
			OAuth2 is easy enough without the lib, see bingo.d line 340ish-380ish.
	)

	History:
		Started April 20, 2024.
+/
module arsd.discord;

// FIXME: it thought it was still alive but showed as not online and idk why. maybe setPulseCallback stopped triggering?

// FIXME: Secure Connect Failed sometimes on trying to reconnect, should prolly just try again after a short period, or ditch the whole thing if reconnectAndResume and try fresh

// FIXME: User-Agent: DiscordBot ($url, $versionNumber)

import arsd.http2;
import arsd.jsvar;

import arsd.core;

import core.time;

static assert(use_arsd_core);

/++
	Base class to represent some object on Discord, e.g. users, channels, etc., through its subclasses.


	Among its implementations are:

	$(LIST
		* [DiscordChannel]
		* [DiscordUser]
		* [DiscordRole]
	)
+/
abstract class DiscordEntity {
	private DiscordRestApi api;
	private string id_;

	protected this(DiscordRestApi api, string id) {
		this.api = api;
		this.id_ = id;
	}

	override string toString() {
		return restType ~ "/" ~ id;
	}

	/++

	+/
	abstract string restType();

	/++

	+/
	final string id() {
		return id_;
	}

	/++
		Gives easy access to its rest api through [arsd.http2.HttpApiClient]'s dynamic dispatch functions.

	+/
	DiscordRestApi.RestBuilder rest() {
		return api.rest[restType()][id()];
	}
}

/++
	Represents something mentionable on Discord with `@name` - roles and users.
+/
abstract class DiscordMentionable : DiscordEntity {
	this(DiscordRestApi api, string id) {
		super(api, id);
	}
}

/++
	https://discord.com/developers/docs/resources/channel
+/
class DiscordChannel : DiscordEntity {
	this(DiscordRestApi api, string id) {
		super(api, id);
	}

	override string restType() {
		return "channels";
	}

	void sendMessage(string message) {
		if(message.length == 0)
			message = "empty message specified";
		var msg = var.emptyObject;
		msg.content = message;
		rest.messages.POST(msg).result;
	}
}

/++

+/
class DiscordRole : DiscordMentionable {
	this(DiscordRestApi api, DiscordGuild guild, string id) {
		this.guild_ = guild;
		super(api, id);
	}

	private DiscordGuild guild_;

	/++

	+/
	DiscordGuild guild() {
		return guild_;
	}

	override string restType() {
		return "roles";
	}
}

/++
	https://discord.com/developers/docs/resources/user
+/
class DiscordUser : DiscordMentionable {
	this(DiscordRestApi api, string id) {
		super(api, id);
	}

	private var cachedData;

	// DiscordGuild selectedGuild;

	override string restType() {
		return "users";
	}

	void addRole(DiscordRole role) {
		// PUT /guilds/{guild.id}/members/{user.id}/roles/{role.id}

		auto thing = api.rest.guilds[role.guild.id].members[this.id].roles[role.id];
		writeln(thing.toUri);

		auto result = api.rest.guilds[role.guild.id].members[this.id].roles[role.id].PUT().result;
	}

	void removeRole(DiscordRole role) {
		// DELETE /guilds/{guild.id}/members/{user.id}/roles/{role.id}

		auto thing = api.rest.guilds[role.guild.id].members[this.id].roles[role.id];
		writeln(thing.toUri);

		auto result = api.rest.guilds[role.guild.id].members[this.id].roles[role.id].DELETE().result;
	}

	private DiscordChannel dmChannel_;

	DiscordChannel dmChannel() {
		if(dmChannel_ is null) {
			var obj = var.emptyObject;
			obj.recipient_id = this.id;
			var result = this.api.rest.users["@me"].channels.POST(obj).result;

			dmChannel_ = new DiscordChannel(api, result.id.get!string);//, result);
		}
		return dmChannel_;
	}

	void sendMessage(string what) {
		dmChannel.sendMessage(what);
	}
}

/++

+/
class DiscordGuild : DiscordEntity {
	this(DiscordRestApi api, string id) {
		super(api, id);
	}

	override string restType() {
		return "guilds";
	}

}


enum InteractionType {
	PING = 1,
	APPLICATION_COMMAND = 2, // the main one
	MESSAGE_COMPONENT = 3,
	APPLICATION_COMMAND_AUTOCOMPLETE = 4,
	MODAL_SUBMIT = 5,
}


/++
	You can create your own slash command handlers by subclassing this and writing methods like

	It will register for you when you connect and call your function when things come in.

	See_Also:
		https://discord.com/developers/docs/interactions/application-commands#bulk-overwrite-global-application-commands
+/
class SlashCommandHandler {
	enum ApplicationCommandOptionType {
		INVALID = 0, // my addition
		SUB_COMMAND = 1,
		SUB_COMMAND_GROUP = 2,
		STRING = 3,
		INTEGER = 4, // double's int part
		BOOLEAN = 5,
		USER = 6,
		CHANNEL = 7,
		ROLE = 8,
		MENTIONABLE = 9,
		NUMBER = 10, // double
		ATTACHMENT = 11,
	}

	/++
		This takes the child type into the parent so we can reflect over your added methods.
		to initialize the reflection info to send to Discord. If you subclass your subclass,
		make sure the grandchild constructor does `super(); registerAll(this);` to add its method
		to the list too, but if you only have one level of child, the compiler will auto-generate
		a constructor for you that calls this.
	+/
	protected this(this This)() {
		registerAll(cast(This) this);
	}

	/++

	+/
	static class InteractionReplyHelper {
		private DiscordRestApi api;
		private CommandArgs commandArgs;

		private this(DiscordRestApi api, CommandArgs commandArgs) {
			this.api = api;
			this.commandArgs = commandArgs;

		}

		/++

		+/
		void reply(string message, bool ephemeral = false) scope {
			replyLowLevel(message, ephemeral);
		}

		/++

		+/
		void replyWithError(scope const(char)[] message) scope {
			if(message.length == 0)
				message = "I am error.";
			replyLowLevel(message.idup, true);
		}

		enum MessageFlags : uint {
			SUPPRESS_EMBEDS        = (1 << 2), // skip the embedded content
			EPHEMERAL              = (1 << 6), // only visible to you
			LOADING                = (1 << 7), // the bot is "thinking"
			SUPPRESS_NOTIFICATIONS = (1 << 12) // skip push/desktop notifications
		}

		void replyLowLevel(string message, bool ephemeral) scope {
			if(message.length == 0)
				message = "empty message";
			var reply = var.emptyObject;
			reply.type = 4; // chat response in message. 5 can be answered quick and edited later if loading, 6 if quick answer, no loading message
			var replyData = var.emptyObject;
			replyData.content = message;
			replyData.flags = ephemeral ? (1 << 6) : 0;
			reply.data = replyData;
			try {
				var result = api.rest.
					interactions[commandArgs.interactionId][commandArgs.interactionToken].callback
					.POST(reply).result;
				writeln(result.toString);
			} catch(Exception e) {
				import std.stdio; writeln(commandArgs);
				writeln(e.toString());
			}
		}
	}


	private bool alreadyRegistered;
	private void register(DiscordRestApi api, string appId) {
		if(alreadyRegistered)
			return;
		auto result = api.rest.applications[appId].commands.PUT(jsonArrayForDiscord).result;
		alreadyRegistered = true;
	}

	private static struct CommandArgs {
		InteractionType interactionType;
		string interactionToken;
		string interactionId;
		string guildId;
		string channelId;

		var interactionData;

		var member;
		var channel;
	}

	private {

		static void validateDiscordSlashCommandName(string name) {
			foreach(ch; name) {
				if(ch != '_' && !(ch >= 'a' && ch <= 'z'))
					throw new InvalidArgumentsException("name", "discord names must be all lower-case with only letters and underscores", LimitedVariant(name));
			}
		}

		static HandlerInfo makeHandler(alias handler, T)(T slashThis) {
			HandlerInfo info;

			// must be all lower case!
			info.name = __traits(identifier, handler);

			validateDiscordSlashCommandName(info.name);

			var cmd = var.emptyObject();
			cmd.name = info.name;
			version(D_OpenD)
				cmd.description = __traits(docComment, handler);
			else
				cmd.description = "";

			if(cmd.description == "")
				cmd.description = "Can't be blank for CHAT_INPUT";

			cmd.type = 1; // CHAT_INPUT

			var optionsArray = var.emptyArray;

			static if(is(typeof(handler) Params == __parameters)) {}

			string[] names;

			// extract parameters
			foreach(idx, param; Params) {
				var option = var.emptyObject;
				auto name = __traits(identifier, Params[idx .. idx + 1]);
				validateDiscordSlashCommandName(name);
				names ~= name;
				option.name = name;
				option.description = "desc";
				option.type = cast(int) applicationComandOptionTypeFromDType!(param);
				// can also add "choices" which limit it to just specific members
				if(option.type) {
					optionsArray ~= option;
				}
			}

			cmd.options = optionsArray;

			info.jsonObjectForDiscord = cmd;
			info.handler = (CommandArgs args, scope InteractionReplyHelper replyHelper, DiscordRestApi api) {
				// extract args
				// call the function
				// send the appropriate reply
				static if(is(typeof(handler) Return == return)) {
					static if(is(Return == void)) {
						__traits(child, slashThis, handler)(fargsFromJson!Params(api, names, args.interactionData, args).tupleof);
						sendHandlerReply("OK", replyHelper, true);
					} else {
						sendHandlerReply(__traits(child, slashThis, handler)(fargsFromJson!Params(api, names, args.interactionData, args).tupleof), replyHelper, false);
					}
				} else static assert(0);
			};

			return info;
		}

		static auto fargsFromJson(Params...)(DiscordRestApi api, string[] names, var obj, CommandArgs args/*, Params defaults*/) {
			static struct Holder {
				// FIXME: default params no work
				Params params;// = defaults;
			}

			Holder holder;
			foreach(idx, ref param; holder.params) {
				setParamFromJson(param, names[idx], api, obj, args);
			}

			return holder;

/+

ync def something(interaction:discord.Interaction):
    await interaction.response.send_message("NOTHING",ephemeral=True)
    # optional (if you want to edit the response later,delete it, or send a followup)
    await interaction.edit_original_response(content="Something")
    await interaction.followup.send("This is a message too.",ephemeral=True)
    await interaction.delete_original_response()
    # if you have deleted the original response you can't edit it or send a followup after it
+/

		}


// {"t":"INTERACTION_CREATE","s":7,"op":0,"d":{"version":1,"type":2,"token":"aW50ZXJhY3Rpb246MTIzMzIyNzE0OTU0NTE3NzE2OTp1Sjg5RE0wMzJiWER2UDRURk5XSWRaUTJtMExBeklWNEtpVEZocTQ4a0VZQ3NWUm9ta3g2SG1JbTBzUm1yWmlUNzQ3eWxpc0FnM0RzUzZHaWtENnRXUDBsdUhERElKSWlaYlFWMlNsZlZXTlFkU3VVQUVWU01PNU9TNFQ5cmFQSw",

// "member":{"user":{"username":"wrathful_vengeance_god_unleashed","public_flags":0,"id":"395786107780071424","global_name":"adr","discriminator":"0","clan":null,"avatar_decoration_data":null,"avatar":"e3c2aacef7920d3a661a19aaab969337"},"unusual_dm_activity_until":null,"roles":[],"premium_since":null,"permissions":"1125899906842623","pending":false,"nick":"adr","mute":false,"joined_at":"2022-08-24T12:37:21.252000+00:00","flags":0,"deaf":false,"communication_disabled_until":null,"avatar":null},

// "locale":"en-US","id":"1233227149545177169","guild_locale":"en-US","guild_id":"1011977515109187704",
// "guild":{"locale":"en-US","id":"1011977515109187704","features":[]},
// "entitlements":[],"entitlement_sku_ids":[],
// "data":{"type":1,"name":"hello","id":"1233221536522174535"},"channel_id":"1011977515109187707",
// "channel":{"type":0,"topic":null,"rate_limit_per_user":0,"position":0,"permissions":"1125899906842623","parent_id":"1011977515109187705","nsfw":false,"name":"general","last_message_id":"1233227103844171806","id":"1011977515109187707","guild_id":"1011977515109187704","flags":0},
// "application_id":"1223724819821105283","app_permissions":"1122573558992465"}}


		template applicationComandOptionTypeFromDType(T) {
			static if(is(T == SendingUser) || is(T == SendingChannel))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.INVALID; // telling it to skip sending this to discord, it purely internal
			else static if(is(T == DiscordRole))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.ROLE;
			else static if(is(T == string))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.STRING;
			else static if(is(T == bool))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.BOOLEAN;
			else static if(is(T : const long))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.INTEGER;
			else static if(is(T : const double))
				enum applicationComandOptionTypeFromDType = ApplicationCommandOptionType.NUMBER;
			else
				static assert(0, T.stringof);
		}

		static var getOptionForName(var obj, string name) {
			foreach(option; obj.options)
				if(option.name == name)
					return option;
			return var.init;
		}

		static void setParamFromJson(T)(ref T param, string name, DiscordRestApi api, var obj, CommandArgs args) {
			static if(is(T == SendingUser)) {
				param = new SendingUser(api, args.member.user.id.get!string, obj.member.user);
			} else static if(is(T == SendingChannel)) {
				param = new SendingChannel(api, args.channel.id.get!string, obj.channel);
			} else static if(is(T == string)) {
				var option = getOptionForName(obj, name);
				if(option.type == cast(int) ApplicationCommandOptionType.STRING)
					param = option.value.get!(typeof(param));
			} else static if(is(T == bool)) {
				var option = getOptionForName(obj, name);
				if(option.type == cast(int) ApplicationCommandOptionType.BOOLEAN)
					param = option.value.get!(typeof(param));
			} else static if(is(T : const long)) {
				var option = getOptionForName(obj, name);
				if(option.type == cast(int) ApplicationCommandOptionType.INTEGER)
					param = option.value.get!(typeof(param));
			} else static if(is(T : const double)) {
				var option = getOptionForName(obj, name);
				if(option.type == cast(int) ApplicationCommandOptionType.NUMBER)
					param = option.value.get!(typeof(param));
			} else static if(is(T == DiscordRole)) {

//"data":{"type":1,"resolved":{"roles":{"1223727548295544865":{"unicode_emoji":null,"tags":{"bot_id":"1223724819821105283"},"position":1,"permissions":"3088","name":"OpenD","mentionable":false,"managed":true,"id":"1223727548295544865","icon":null,"hoist":false,"flags":0,"description":null,"color":0}}},"options":[{"value":"1223727548295544865","type":8,"name":"role"}],"name":"add_role","id":"1234130839315677226"},"channel_id":"1011977515109187707","channel":{"type":0,"topic":null,"rate_limit_per_user":0,"position":0,"permissions":"1125899906842623","parent_id":"1011977515109187705","nsfw":false,"name":"general","last_message_id":"1234249771745804399","id":"1011977515109187707","guild_id":"1011977515109187704","flags":0},"application_id":"1223724819821105283","app_permissions":"1122573558992465"}}

// resolved gives you some precache info

				var option = getOptionForName(obj, name);
				if(option.type == cast(int) ApplicationCommandOptionType.ROLE)
					param = new DiscordRole(api, new DiscordGuild(api, args.guildId), option.value.get!string);
				else
					param = null;
			} else {
				static assert(0, "Bad type " ~ T.stringof);
			}
		}

		static void sendHandlerReply(T)(T ret, scope InteractionReplyHelper replyHelper, bool ephemeral) {
			import std.conv; // FIXME
			replyHelper.reply(to!string(ret), ephemeral);
		}

		void registerAll(T)(T t) {
			assert(t !is null);
			foreach(memberName; __traits(derivedMembers, T))
				static if(memberName != "__ctor") { // FIXME
					HandlerInfo hi = makeHandler!(__traits(getMember, T, memberName))(t);
					registerFromRuntimeInfo(hi);
				}
		}

		void registerFromRuntimeInfo(HandlerInfo info) {
			handlers[info.name] = info.handler;
			if(jsonArrayForDiscord is var.init)
				jsonArrayForDiscord = var.emptyArray;
			jsonArrayForDiscord ~= info.jsonObjectForDiscord;
		}

		alias InternalHandler = void delegate(CommandArgs args, scope InteractionReplyHelper replyHelper, DiscordRestApi api);
		struct HandlerInfo {
			string name;
			InternalHandler handler;
			var jsonObjectForDiscord;
		}
		InternalHandler[string] handlers;
		var jsonArrayForDiscord;
	}
}

/++
	A SendingUser is a special DiscordUser type that just represents the person who sent the message.

	It exists so you can use it in a function parameter list that is auto-mapped to a message handler.
+/
class SendingUser : DiscordUser {
	private this(DiscordRestApi api, string id, var initialCache) {
		super(api, id);
	}
}

class SendingChannel : DiscordChannel {
	private this(DiscordRestApi api, string id, var initialCache) {
		super(api, id);
	}
}

// SendingChannel
// SendingMessage

/++
	Use as a UDA

	A file of choices for the given option. The exact interpretation depends on the type but the general rule is one option per line, id or name.

	FIXME: watch the file for changes for auto-reload and update on the discord side

	FIXME: NOT IMPLEMENTED
+/
struct ChoicesFromFile {
	string filename;
}

/++
	Most the magic is inherited from [arsd.http2.HttpApiClient].
+/
class DiscordRestApi : HttpApiClient!() {
	/++
		Creates an API client.

		Params:
			token = the bot authorization token you got from Discord
			yourBotUrl = a URL for your bot, used to identify the user-agent. Discord says it should not be null, but that seems to work.
			yourBotVersion = version number (or whatever) for your bot, used as part of the user-agent. Should not be null according to the docs but it doesn't seem to matter in practice.
	+/
	this(string botToken, string yourBotUrl, string yourBotVersion) {
		this.authType = "Bot";
		super("https://discord.com/api/v10/", botToken);
	}
}

/++

+/
class DiscordGatewayConnection {
	private WebSocket websocket_;
	private long lastSequenceNumberReceived;
	private string token;
	private DiscordRestApi api_;

	/++
		An instance to the REST api object associated with your connection.
	+/
	public final DiscordRestApi api() {
		return this.api_;
	}

	/++

	+/
	protected final WebSocket websocket() {
		return websocket_;
	}

	// https://discord.com/developers/docs/topics/opcodes-and-status-codes#gateway-gateway-opcodes
	enum OpCode {
		Dispatch = 0, // recv
		Heartbeat = 1, // s/r
		Identify = 2, // s
		PresenceUpdate = 3, // s
		VoiceStateUpdate = 4, // s
		Resume = 6, // s
		Reconnect = 7, // r
		RequestGuildMembers = 8, // s
		InvalidSession = 9, // r - you should reconnect and identify/resume
		Hello = 10, // r
		HeartbeatAck = 11, // r
	}

	enum DisconnectCodes {
		UnknownError = 4000, // t
		UnknownOpcode = 4001, // t (user error)
		DecodeError = 4002, // t (user error)
		NotAuthenticated = 4003, // t (user error)
		AuthenticationFailed = 4004, // f (user error)
		AlreadyAuthenticated = 4005, // t (user error)
		InvalidSeq = 4007, // t
		RateLimited = 4008, // t
		SessionTimedOut = 4009, // t
		InvalidShard = 4010, // f (user error)
		ShardingRequired = 4011, // f
		InvalidApiVersion = 4012, // f
		InvalidIntents = 4013, // f
		DisallowedIntents = 4014, // f
	}

	private string cachedGatewayUrl;

	/++
		Prepare a gateway connection. After you construct it, you still need to call [connect].

		Params:
			token = the bot authorization token you got from Discord
			yourBotUrl = a URL for your bot, used to identify the user-agent. Discord says it should not be null, but that seems to work.
			yourBotVersion = version number (or whatever) for your bot, used as part of the user-agent. Should not be null according to the docs but it doesn't seem to matter in practice.
	+/
	public this(string token, string yourBotUrl, string yourBotVersion) {
		this.token = token;
		this.api_ = new DiscordRestApi(token, yourBotUrl, yourBotVersion);
	}

	/++
		Allows you to set up a subclass of [SlashCommandHandler] for handling discord slash commands.
	+/
	final void slashCommandHandler(SlashCommandHandler t) {
		if(slashCommandHandler_ !is null && t !is null)
			throw ArsdException!"SlashCommandHandler is already set"();
		slashCommandHandler_ = t;
		if(t && applicationId.length)
			t.register(api, applicationId);
	}
	private SlashCommandHandler slashCommandHandler_;

	/++

	+/
	protected void handleWebsocketClose(WebSocket.CloseEvent closeEvent) {
		import std.stdio; writeln(closeEvent);
		if(heartbeatTimer)
			heartbeatTimer.cancel();

		if(closeEvent.code == 1006 || closeEvent.code == 1001) {
			reconnectAndResume();
		} else {
			// otherwise, unless we were asked by the api user to close, let's try reconnecting
			// since discord just does discord things.
			websocket_ = null;
			connect();
		}
	}

	/++
	+/
	void close() {
		close(1000, null);
	}

	/// ditto
	void close(int reason, string reasonText) {
		if(heartbeatTimer)
			heartbeatTimer.cancel();

		websocket_.onclose = null;
		websocket_.ontextmessage = null;
		websocket_.onbinarymessage = null;
		websocket.close(reason, reasonText);
		websocket_ = null;
	}

	/++
	+/
	protected void handleWebsocketMessage(in char[] msg) {
		var m = var.fromJson(msg.idup);

		OpCode op = cast(OpCode) m.op.get!int;
		var data = m.d;

		switch(op) {
			case OpCode.Dispatch:
				// these are null if op != 0
				string eventName = m.t.get!string;
				long seqNumber = m.s.get!long;

				if(seqNumber > lastSequenceNumberReceived)
					lastSequenceNumberReceived = seqNumber;

				eventReceived(eventName, data);
			break;
			case OpCode.Hello:
				// the hello heartbeat_interval is in milliseconds
				if(slashCommandHandler_ !is null && applicationId.length)
					slashCommandHandler_.register(api, applicationId);

				setHeartbeatInterval(data.heartbeat_interval.get!int);
			break;
			case OpCode.Heartbeat:
				sendHeartbeat();
			break;
			case OpCode.HeartbeatAck:
				mostRecentHeartbeatAckRecivedAt = MonoTime.currTime;
			break;
			case OpCode.Reconnect:
				writeln("reconnecting");
				this.close(4999, "Reconnect requested");
				reconnectAndResume();
			break;
			case OpCode.InvalidSession:
				writeln("starting new session");

				close();
				connect(); // try starting a brand new session
			break;
			default:
				// ignored
		}
	}

	protected void reconnectAndResume() {
		this.websocket_ = new WebSocket(Uri(this.resume_gateway_url));

		websocket.onmessage = &handleWebsocketMessage;
		websocket.onclose = &handleWebsocketClose;

		websocketConnectInLoop();

		var resumeData = var.emptyObject;
		resumeData.token = this.token;
		resumeData.session_id = this.session_id;
		resumeData.seq = lastSequenceNumberReceived;

		sendWebsocketCommand(OpCode.Resume, resumeData);

		// the close event will cancel the heartbeat and thus we need to restart it
		if(requestedHeartbeat)
			setHeartbeatInterval(requestedHeartbeat);
	}

	/++
	+/
	protected void eventReceived(string eventName, var data) {
		// FIXME: any time i get an event i could prolly spin it off into an independent async task
		switch(eventName) {
			case "INTERACTION_CREATE":
				var member = data.member; // {"user":{"username":"wrathful_vengeance_god_unleashed","public_flags":0,"id":"395786107780071424","global_name":"adr","discriminator":"0","clan":null,"avatar_decoration_data":null,"avatar":"e3c2aacef7920d3a661a19aaab969337"},"unusual_dm_activity_until":null,"roles":[],"premium_since":null,"permissions":"1125899906842623","pending":false,"nick":"adr","mute":false,"joined_at":"2022-08-24T12:37:21.252000+00:00","flags":0,"deaf":false,"communication_disabled_until":null,"avatar":null}

				SlashCommandHandler.CommandArgs commandArgs;

				commandArgs.interactionType = cast(InteractionType) data.type.get!int;
				commandArgs.interactionToken = data.token.get!string;
				commandArgs.interactionId = data.id.get!string;
				commandArgs.guildId = data.guild_id.get!string;
				commandArgs.channelId = data.channel_id.get!string;
				commandArgs.member = member;
				commandArgs.channel = data.channel;

				commandArgs.interactionData = data.data;
				// data.data : type/name/id. can use this to determine what function to call. prolly will include other info too
				// "data":{"type":1,"name":"hello","id":"1233221536522174535"}

				// application_id and app_permissions and some others there too but that doesn't seem important

				/+
					replies:
					https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-response-object-interaction-callback-type
				+/

				scope SlashCommandHandler.InteractionReplyHelper replyHelper = new SlashCommandHandler.InteractionReplyHelper(api, commandArgs);

				Exception throwExternally;

				try {
					if(slashCommandHandler_ is null)
						throwExternally = ArsdException!"No slash commands registered"();
					else {
						auto cmdName = commandArgs.interactionData.name.get!string;
						if(auto pHandler = cmdName in slashCommandHandler_.handlers) {
							(*pHandler)(commandArgs, replyHelper, api);
						} else {
							throwExternally = ArsdException!"Unregistered slash command"(cmdName);
						}
					}
				} catch(ArsdExceptionBase e) {
					const(char)[] msg = e.message;
					if(msg.length == 0)
						msg = "I am error.";

					e.getAdditionalPrintableInformation((string name, in char[] value) {
						msg ~= ("\n");
						msg ~= (name);
						msg ~= (": ");
						msg ~= (value);
					});

					replyHelper.replyWithError(msg);
				} catch(Exception e) {
					replyHelper.replyWithError(e.message);
				}

				if(throwExternally !is null)
					throw throwExternally;
			break;
			case "READY":
				this.session_id = data.session_id.get!string;
				this.resume_gateway_url = data.resume_gateway_url.get!string;
				this.applicationId_ = data.application.id.get!string;

				if(slashCommandHandler_ !is null && applicationId.length)
					slashCommandHandler_.register(api, applicationId);
			break;

			default:
		}
	}

	private string session_id;
	private string resume_gateway_url;
	private string applicationId_;

	/++
		Returns your application id. Only available after the connection is established.
	+/
	public string applicationId() {
		return applicationId_;
	}

	private arsd.core.Timer heartbeatTimer;
	private int requestedHeartbeat;
	private bool requestedHeartbeatSet;
	//private int heartbeatsSent;
	//private int heartbeatAcksReceived;
	private MonoTime mostRecentHeartbeatAckRecivedAt;

	protected void sendHeartbeat() {
	arsd.core.writeln("sendHeartbeat");
		sendWebsocketCommand(OpCode.Heartbeat, var(lastSequenceNumberReceived));
	}

	private final void sendHeartbeatThunk() {
		this.sendHeartbeat(); // also virtualizes which wouldn't happen with &sendHeartbeat
		if(requestedHeartbeatSet == false) {
			heartbeatTimer.changeTime(requestedHeartbeat, true);
			requestedHeartbeatSet = true;
		} else {
			if(MonoTime.currTime - mostRecentHeartbeatAckRecivedAt > 2 * requestedHeartbeat.msecs) {
				// throw ArsdException!"connection has no heartbeat"(); // FIXME: pass the info?
				websocket.close(1006, "heartbeat unanswered");
				reconnectAndResume();
			}
		}
	}

	/++
	+/
	protected void setHeartbeatInterval(int msecs) {
		requestedHeartbeat = msecs;
		requestedHeartbeatSet = false;

		if(heartbeatTimer is null) {
			heartbeatTimer = new arsd.core.Timer;
			heartbeatTimer.setPulseCallback(&sendHeartbeatThunk);
		}

		// the first one is supposed to have random jitter
		// so we'll do that one-off (but with a non-zero time
		// since my timers don't like being run twice in one loop
		// iteration) then that first one will set the repeating time
		import std.random;
		auto firstBeat = std.random.uniform(10, msecs);
		heartbeatTimer.changeTime(firstBeat, false);
	}

	/++

	+/
	void sendWebsocketCommand(OpCode op, var d) {
		assert(websocket !is null, "call connect before sending commands");

		var cmd = var.emptyObject;
		cmd.d = d;
		cmd.op = cast(int) op;
		websocket.send(cmd.toJson());
	}

	/++

	+/
	void connect() {
		assert(websocket is null, "do not call connect twice");

		if(cachedGatewayUrl is null) {
			auto obj = api.rest.gateway.bot.GET().result;
			cachedGatewayUrl = obj.url.get!string;
		}

		this.websocket_ = new WebSocket(Uri(cachedGatewayUrl));

		websocket.onmessage = &handleWebsocketMessage;
		websocket.onclose = &handleWebsocketClose;

		websocketConnectInLoop();

		var d = var.emptyObject;
		d.token = token;
			// FIXME?
		d.properties = [
			"os": "linux",
			"browser": "arsd.discord",
			"device": "arsd.discord",
		];

		sendWebsocketCommand(OpCode.Identify, d);
	}

	void websocketConnectInLoop() {
		// FIXME: if the connect fails we should set a timer and try
		// again, but if it fails then, quit. at least if it is not a websocket reply
		// cuz it could be discord went down or something.

		import core.time;
		auto d = 1.seconds;
		int count = 0;

		try_again:

		try {
			this.websocket_.connect();
		} catch(Exception e) {
			import core.thread;
			Thread.sleep(d);
			d *= 2;
			count++;
			if(count == 10)
				throw e;

			goto try_again;
		}
	}


}

class DiscordRpcConnection {

	// this.websocket_ = new WebSocket(Uri("ws://127.0.0.1:6463/?v=1&client_id=XXXXXXXXXXXXXXXXX&encoding=json"), config);
	// websocket.send(`{ "nonce": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", "args": { "access_token": "XXXXXXXXXXXXXXXXXXXXX" }, "cmd": "AUTHENTICATE" }`);
	// writeln(websocket.waitForNextMessage.textData);

	// these would tell me user names and ids when people join/leave but it needs authentication alas

	/+
	websocket.send(`{ "nonce": "ce9a6de3-31d0-4767-a8e9-4818c5690015", "args": {
    "guild_id": "SSSSSSSSSSSSSSSS",
    "channel_id": "CCCCCCCCCCCCCCCCC"
  },
  "evt": "VOICE_STATE_CREATE",
  "cmd": "SUBSCRIBE"
}`);
	writeln(websocket.waitForNextMessage.textData);

	websocket.send(`{ "nonce": "de9a6de3-31d0-4767-a8e9-4818c5690015", "args": {
    "guild_id": "SSSSSSSSSSSSSSSS",
    "channel_id": "CCCCCCCCCCCCCCCCC"
  },
  "evt": "VOICE_STATE_DELETE",
  "cmd": "SUBSCRIBE"
}`);

		websocket.onmessage = delegate(in char[] msg) {
			writeln(msg);

			import arsd.jsvar;
			var m = var.fromJson(msg.idup);
			if(m.cmd == "DISPATCH") {
				if(m.evt == "SPEAKING_START") {
					//setSpeaking(m.data.user_id.get!ulong, true);
				} else if(m.evt == "SPEAKING_STOP") {
					//setSpeaking(m.data.user_id.get!ulong, false);
				}
			}
		};


	+/


}
