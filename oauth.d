/// Implementations of OAuth 1.0 server and client. You probably don't need this anymore; I haven't used it for years.
module arsd.oauth;

import arsd.curl;
import arsd.uri;
import arsd.cgi : Cgi;
import std.array;
static import std.uri;
static import std.algorithm;
import std.conv;
import std.string;
import std.random;
import std.base64;
import std.exception;
import std.datetime;


static if(__VERSION__ <= 2076) {
	// compatibility shims with gdc
	enum JSONType {
		object = JSON_TYPE.OBJECT,
		null_ = JSON_TYPE.NULL,
		false_ = JSON_TYPE.FALSE,
		true_ = JSON_TYPE.TRUE,
		integer = JSON_TYPE.INTEGER,
		float_ = JSON_TYPE.FLOAT,
		array = JSON_TYPE.ARRAY,
		string = JSON_TYPE.STRING,
		uinteger = JSON_TYPE.UINTEGER
	}
}


///////////////////////////////////////

class FacebookApiException : Exception {
	public this(string response, string token = null, string scopeRequired = null) {
		this.token = token;
		this.scopeRequired = scopeRequired;
		super(response ~ "\nToken: " ~ token ~ "\nScope: " ~ scopeRequired);
	}

	string token;
	string scopeRequired;
}


import arsd.curl;
import arsd.sha;

import std.digest.md;

import std.file;


// note when is a d_time, so unix_timestamp * 1000
Variant[string] postToFacebookWall(string[] info, string id, string message, string picture = null, string link = null, long when = 0, string linkDescription = null) {
	string url = "https://graph.facebook.com/" ~ id ~ "/feed";

	string data = "access_token=" ~ std.uri.encodeComponent(info[1]);
	data ~= "&message=" ~ std.uri.encodeComponent(message);

	if(picture !is null && picture.length)
		data ~= "&picture=" ~ std.uri.encodeComponent(picture);
	if(link !is null && link.length)
		data ~= "&link=" ~ std.uri.encodeComponent(link);
	if(when) {
		data ~= "&scheduled_publish_time=" ~ to!string(when / 1000);
		data ~= "&published=false";
	}
	if(linkDescription.length)
		data ~= "&description=" ~ std.uri.encodeComponent(linkDescription);

	auto response = curl(url, data);

	auto res = jsonToVariant(response);
/+
{"error":{"type":"OAuthException","message":"An active access token must be used to query information about the current user."}}
+/
	// assert(0, response);

	auto var = res.get!(Variant[string]);


	if("error" in var) {
		auto error = var["error"].get!(Variant[string]);

		throw new FacebookApiException(error["message"].get!string, info[1],
			"scope" in error ? error["scope"].get!string : "publish_stream");
	}

	return var;
}

version(with_arsd_jsvar) {
	import arsd.jsvar;
	var fbGraph(string token, string id, bool useCache = false, long maxCacheHours = 2) {
		auto response = fbGraphImpl(token, id, useCache, maxCacheHours);

		var ret = var.emptyObject;

		if(response == "false") {
			var v1 = id[1..$];
			ret["id"] = v1;
			ret["name"] = v1 = "Private";
			ret["description"] = v1 = "This is a private facebook page. Please make it public in Facebook if you want to promote it.";
			ret["link"] = v1 = "http://facebook.com?profile.php?id=" ~ id[1..$];
			ret["is_false"] = true;
			return ret;
		}

		ret = var.fromJson(response);

		if("error" in ret) {
			auto error = ret.error;

			if("message" in error)
				throw new FacebookApiException(error["message"].get!string, token.length > 1 ? token : null,
					"scope" in error ? error["scope"].get!string : null);
			else
				throw new FacebookApiException("couldn't get FB info");
		}

		return ret;
	}
}

Variant[string] fbGraph(string[] info, string id, bool useCache = false, long maxCacheHours = 2) {
	auto response = fbGraphImpl(info[1], id, useCache, maxCacheHours);

	if(response == "false") {
		//throw new Exception("This page is private. Please make it public in Facebook.");
		// we'll make dummy data so this still returns

		Variant[string] ret;

		Variant v1 = id[1..$];
		ret["id"] = v1;
		ret["name"] = v1 = "Private";
		ret["description"] = v1 = "This is a private facebook page. Please make it public in Facebook if you want to promote it.";
		ret["link"] = v1 = "http://facebook.com?profile.php?id=" ~ id[1..$];
		ret["is_false"] = true;
		return ret;
	}

	auto res = jsonToVariant(response);
/+
{"error":{"type":"OAuthException","message":"An active access token must be used to query information about the current user."}}
+/
	// assert(0, response);

	auto var = res.get!(Variant[string]);

	if("error" in var) {
		auto error = var["error"].get!(Variant[string]);

		if("message" in error)
		throw new FacebookApiException(error["message"].get!string, info.length > 1 ? info[1] : null,
			"scope" in error ? error["scope"].get!string : null);
		else
			throw new FacebookApiException("couldn't get FB info");
	}

	return var;

}

// note ids=a,b,c works too. it returns an associative array of the ids requested.
string fbGraphImpl(string info, string id, bool useCache = false, long maxCacheHours = 2) {
	string response;

	string cacheFile;

	char c = '?';

	if(id.indexOf("?") != -1)
		c = '&';

	string url;

	if(id[0] != '/')
		id = "/" ~ id;

	if(info !is null)
		url = "https://graph.facebook.com" ~ id
			~ c ~ "access_token=" ~ info ~ "&format=json";
	else
		url = "http://graph.facebook.com" ~ id
			~ c ~ "format=json";

	// this makes pagination easier. the initial / is there because it is added above
	if(id.indexOf("/http://") == 0 || id.indexOf("/https://") == 0)
		url = id[1 ..$];

	if(useCache)
		cacheFile = "/tmp/fbGraphCache-" ~ hashToString(SHA1(url));

	if(useCache) {
		if(std.file.exists(cacheFile)) {
			if((Clock.currTime() - std.file.timeLastModified(cacheFile)) < dur!"hours"(maxCacheHours)) {
				response = std.file.readText(cacheFile);
				goto haveResponse;
			}
		}
	}

	try {
		response = curl(url);
	} catch(CurlException e) {
		throw new FacebookApiException(e.msg);
	}

	if(useCache) {
		std.file.write(cacheFile, response);
	}

    haveResponse:
	assert(response.length);

	return response;
}



string[string][] getBasicDataFromVariant(Variant[string] v) {
	auto items = v["data"].get!(Variant[]);
	return getBasicDataFromVariant(items);
}

string[string][] getBasicDataFromVariant(Variant[] items) {
	string[string][] ret;

	foreach(item; items) {
		auto i = item.get!(Variant[string]);

		string[string] l;

		foreach(k, v; i) {
			l[k] = to!string(v);
		}

		ret ~= l;
	}

	return ret;
}


/////////////////////////////////////











/* ******************************* */

/*         OAUTH   1.0             */

/* ******************************* */


struct OAuthParams {
	string apiKey;
	string apiSecret;
	string baseUrl;
	string requestTokenPath;
	string accessTokenPath;
	string authorizePath;
}

OAuthParams twitter(string apiKey, string apiSecret) {
	OAuthParams params;

	params.apiKey = apiKey;
	params.apiSecret = apiSecret;

	params.baseUrl = "https://api.twitter.com";
	//params.baseUrl = "http://twitter.com";
	params.requestTokenPath = "/oauth/request_token";
	params.authorizePath = "/oauth/authorize";
	params.accessTokenPath = "/oauth/access_token";

	return params;
}

OAuthParams tumblr(string apiKey, string apiSecret) {
	OAuthParams params;

	params.apiKey = apiKey;
	params.apiSecret = apiSecret;

	params.baseUrl = "http://www.tumblr.com";
	params.requestTokenPath = "/oauth/request_token";
	params.authorizePath = "/oauth/authorize";
	params.accessTokenPath = "/oauth/access_token";

	return params;
}

OAuthParams linkedIn(string apiKey, string apiSecret) {
	OAuthParams params;

	params.apiKey = apiKey;
	params.apiSecret = apiSecret;

	params.baseUrl = "https://api.linkedin.com";
	params.requestTokenPath = "/uas/oauth/requestToken";
	params.accessTokenPath = "/uas/oauth/accessToken";
	params.authorizePath = "/uas/oauth/authorize";

	return params;
}

OAuthParams aWeber(string apiKey, string apiSecret) {
	OAuthParams params;

	params.apiKey = apiKey;
	params.apiSecret = apiSecret;

	params.baseUrl = "https://auth.aweber.com";
	params.requestTokenPath = "/1.1/oauth/request_token";
	params.accessTokenPath = "/1.1/oauth/access_token";
	params.authorizePath = "/1.1/oauth/authorize";

	// API Base: https://api.aweber.com/1.0/

	return params;
}


string tweet(OAuthParams params, string oauthToken, string tokenSecret, string message) {
	assert(oauthToken.length);
	assert(tokenSecret.length);

	auto args = [
		"oauth_token" : oauthToken,
		"token_secret" : tokenSecret,
	];

	auto data = "status=" ~ rawurlencode(message);//.replace("%3F", "?");//encodeVariables(["status" : message]);

	auto ret = curlOAuth(params, "https://api.twitter.com" ~ "/1.1/statuses/update.json", args, "POST", data);

	auto val = jsonToVariant(ret).get!(Variant[string]);
	if("id_str" !in val)
		throw new Exception("bad result from twitter: " ~ ret);
	return val["id_str"].get!string;
}

import std.file;
/**
	Redirects the user to the authorize page on the provider's website.
*/
void authorizeStepOne(Cgi cgi, OAuthParams params, string oauthCallback = null, string additionalOptions = null, string[string] additionalTokenArgs = null) {
	if(oauthCallback is null) {
		oauthCallback = cgi.getCurrentCompleteUri();
		if(oauthCallback.indexOf("?") == -1)
			oauthCallback ~= "?oauth_step=two";
		else
			oauthCallback ~= "&oauth_step=two";
	}

	string[string] args;
	if(oauthCallback.length)
		args["oauth_callback"] = oauthCallback;

	//foreach(k, v; additionalTokenArgs)
		//args[k] = v;

	auto moreArgs = encodeVariables(additionalTokenArgs);
	if(moreArgs.length)
		moreArgs = "?" ~ moreArgs;
	auto ret = curlOAuth(params, params.baseUrl ~ params.requestTokenPath ~ moreArgs,
	 		args, "POST", "", "");
	auto vals = decodeVariables(ret);

	if("oauth_problem" in vals)
		throw new Exception("OAuth problem: " ~ vals["oauth_problem"][0]);

	if(vals.keys.length < 2)
		throw new Exception(ret);

	///vals["fuck_you"] = [params.baseUrl ~ params.requestTokenPath];

	auto oauth_token = vals["oauth_token"][0];
	auto oauth_secret = vals["oauth_token_secret"][0];

	// need to save the secret for later
	std.file.write("/tmp/oauth-token-secret-" ~ oauth_token,
		oauth_secret);

	// FIXME: make sure this doesn't break twitter etc
	if("login_url" in vals) // apparently etsy does it this way...
		cgi.setResponseLocation(vals["login_url"][0]);
	else
		cgi.setResponseLocation(params.baseUrl ~ params.authorizePath ~ "?" ~(additionalOptions.length ? (additionalOptions ~ "&") : "")~ "oauth_token=" ~ oauth_token);
}

/**
	Gets the final token, given the stuff from step one. This should be called
	from the callback in step one.

	Returns [token, secret, raw original data (for extended processing - twitter also sends the screen_name and user_id there)]
*/
string[] authorizeStepTwo(const(Cgi) cgi, OAuthParams params) {
	if("oauth_problem" in cgi.get)
		throw new Exception("OAuth problem: " ~ cgi.get["oauth_problem"]);

	string token = cgi.get["oauth_token"];
	string verifier = cgi.get["oauth_verifier"];

	// reload from file written above. FIXME: clean up old shit too
	string secret = std.file.readText("/tmp/oauth-token-secret-" ~ token);
	// don't need it anymore...
	std.file.remove("/tmp/oauth-token-secret-" ~ token);


	auto ret = curlOAuth(params, params.baseUrl ~ params.accessTokenPath,
		["oauth_token" : token,
		 "oauth_verifier" : verifier,
		 "token_secret" : secret], "POST", "", "");

	auto vars = decodeVariables(ret);

	return [vars["oauth_token"][0], vars["oauth_token_secret"][0], ret];
}



/**
	Note in oauthValues:
		It creates the nonce, signature_method, version, consumer_key, and timestamp
		ones inside this function - you don't have to do it.

		Just put in the values specific to your call.

	oauthValues["token_secret"] if present, is concated into the signing string. Don't
	put it in for the early steps!
*/

import core.stdc.stdlib;

string curlOAuth(OAuthParams auth, string url, string[string] oauthValues, string method = null,string data = null, string contentType = "application/x-www-form-urlencoded") {

	//string oauth_callback; // from user

	oauthValues["oauth_consumer_key"] = 	auth.apiKey;
	oauthValues["oauth_nonce"] = 		makeNonce();
	oauthValues["oauth_signature_method"] = "HMAC-SHA1";

	oauthValues["oauth_timestamp"] = 	to!string(Clock.currTime().toUTC().toUnixTime());
	oauthValues["oauth_version"] = 		"1.0";

	auto questionMark = std.string.indexOf(url, "?");

	string signWith = std.uri.encodeComponent(auth.apiSecret) ~ "&";
	if("token_secret" in oauthValues) {
		signWith ~= std.uri.encodeComponent(oauthValues["token_secret"]);
		oauthValues.remove("token_secret");
	}

	if(method is null)
		method = data is null ? "GET" : "POST";

	auto baseString = getSignatureBaseString(
			method,
			questionMark == -1 ? url : url[0..questionMark],
			questionMark == -1 ? "" : url[questionMark+1 .. $],
			oauthValues,
			contentType == "application/x-www-form-urlencoded" ? data : null
		);

	string oauth_signature = /*std.uri.encodeComponent*/(cast(string)
	    Base64.encode(mhashSign(baseString, signWith, MHASH_SHA1)));

	oauthValues["oauth_signature"] = oauth_signature;

	string oauthHeader;
	bool outputted = false;
	Pair[] pairs;
	foreach(k, v; oauthValues) {
		pairs ~= Pair(k, v);
	}

	foreach(pair; std.algorithm.sort(pairs)) {
		if(outputted)
			oauthHeader ~= ", ";
		else
			outputted = true;

		oauthHeader ~= pair.output(true);
	}

	return curlAuth(url, data, null, null, contentType, method, ["Authorization: OAuth " ~ oauthHeader]);
}

bool isOAuthRequest(Cgi cgi) {
	if(cgi.authorization.length < 5 || cgi.authorization[0..5] != "OAuth")
		return false;
	return true;
}

string getApiKeyFromRequest(Cgi cgi) {
	enforce(isOAuthRequest(cgi));
	auto variables = split(cgi.authorization[6..$], ",");

	foreach(var; variables)
		if(var.startsWith("oauth_consumer_key"))
			return var["oauth_consumer_key".length + 3 .. $ - 1]; // trimming quotes too
	throw new Exception("api key not present");
}

string getTokenFromRequest(Cgi cgi) {
	enforce(isOAuthRequest(cgi));
	auto variables = split(cgi.authorization[6..$], ",");

	foreach(var; variables)
		if(var.startsWith("oauth_token"))
			return var["oauth_token".length + 3 .. $ - 1]; // trimming quotes too
	return null;
}

// FIXME check timestamp and maybe nonce too

bool isSignatureValid(Cgi cgi, string apiSecret, string tokenSecret) {
	enforce(isOAuthRequest(cgi));
	auto variables = split(cgi.authorization[6..$], ",");

	string[string] oauthValues;
	foreach(var; variables) {
		auto it = var.split("=");
		oauthValues[it[0]] = it[1][1 .. $ - 1]; // trimming quotes
	}

	auto url = cgi.getCurrentCompleteUri();

	auto questionMark = std.string.indexOf(url, "?");

	string signWith = std.uri.encodeComponent(apiSecret) ~ "&";
	if(tokenSecret.length)
		signWith ~= std.uri.encodeComponent(tokenSecret);

	auto method = to!string(cgi.requestMethod);

	if("oauth_signature" !in oauthValues)
		return false;

	auto providedSignature = oauthValues["oauth_signature"];

	oauthValues.remove("oauth_signature");

	string oauth_signature = std.uri.encodeComponent(cast(string)
	    Base64.encode(mhashSign(
		getSignatureBaseString(
			method,
			questionMark == -1 ? url : url[0..questionMark],
			questionMark == -1 ? "" : url[questionMark+1 .. $],
			oauthValues,
			cgi.postArray // FIXME: if this was a file upload, this isn't actually right
		), signWith, MHASH_SHA1)));

	return oauth_signature == providedSignature;

}

string makeNonce() {
	auto val = to!string(uniform(uint.min, uint.max)) ~ to!string(Clock.currTime().stdTime);

	return val;
}

struct Pair {
	string name;
	string value;

	string output(bool useQuotes = false) {
		if(useQuotes)
			return std.uri.encodeComponent(name) ~ "=\"" ~ rawurlencode(value) ~ "\"";
		else
			return std.uri.encodeComponent(name) ~ "=" ~ rawurlencode(value);
	}

	int opCmp(Pair rhs) {
		// FIXME: is name supposed to be encoded?
		int val = std.string.cmp(name, rhs.name);

		if(val == 0)
			val = std.string.cmp(value, rhs.value);

		return val;
	}
}
string getSignatureBaseString(
	string method,
	string protocolHostAndPath,
	string queryStringContents,
	string[string] authorizationHeaderContents,
	in string[][string] postArray)
{
	string baseString;

	baseString ~= method;
	baseString ~= "&";
	baseString ~= std.uri.encodeComponent(protocolHostAndPath);
	baseString ~= "&";

	auto getArray = decodeVariables(queryStringContents);

	Pair[] pairs;

	foreach(k, vals; getArray)
		foreach(v; vals)
			pairs ~= Pair(k, v);
	foreach(k, vals; postArray)
		foreach(v; vals)
			pairs ~= Pair(k, v);
	foreach(k, v; authorizationHeaderContents)
		pairs ~= Pair(k, v);

	bool outputted = false;

	string params;
	foreach(pair; std.algorithm.sort(pairs)) {
		if(outputted)
			params ~= "&";
		else
			outputted = true;
		params ~= pair.output();
	}

	baseString ~= std.uri.encodeComponent(params);

	return baseString;
}


string getSignatureBaseString(
	string method,
	string protocolHostAndPath,
	string queryStringContents,
	string[string] authorizationHeaderContents,
	string postBodyIfWwwEncoded)
{
	return getSignatureBaseString(
		method,
		protocolHostAndPath,
		queryStringContents,
		authorizationHeaderContents,
		decodeVariables(postBodyIfWwwEncoded));
}

/***************************************/

//     OAuth 2.0 as used by Facebook   //

/***************************************/

immutable(ubyte)[] base64UrlDecode(string e) {
	string encoded = e.idup;
	while (encoded.length % 4) {
		encoded ~= "="; // add padding
	}

	// convert base64 URL to standard base 64
	encoded = encoded.replace("-", "+");
	encoded = encoded.replace("_", "/");

	auto ugh = Base64.decode(encoded);
	return assumeUnique(ugh);
}

Ret parseSignedRequest(Ret = Variant)(in string req, string apisecret) {
	auto parts = req.split(".");

	immutable signature = parts[0];
	immutable jsonEncoded = parts[1];

	auto expected = mhashSign(jsonEncoded, apisecret, MHASH_SHA256);
	auto got = base64UrlDecode(signature);

	enforce(expected == got, "Signatures didn't match");

	auto json = cast(string) base64UrlDecode(jsonEncoded);

	static if(is(Ret == Variant))
		return jsonToVariant(json);
	else
		return Ret.fromJson(json);
}

string stripWhitespace(string w) {
	return w.replace("\t", "").replace("\n", "").replace(" ", "");
}

string translateCodeToAccessToken(string code, string redirectUrl, string appId, string apiSecret) {
	string res = curl(stripWhitespace("https://graph.facebook.com/oauth/access_token?
		client_id="~appId~"&redirect_uri="~std.uri.encodeComponent(redirectUrl)~"&
		client_secret="~apiSecret~"&code=" ~ std.uri.encodeComponent(code)
	));

	if(res.indexOf("access_token=") == -1) {
		throw new Exception("Couldn't translate code to access token. [" ~ res ~ "]");
	}

	auto vars = decodeVariablesSingle(res);
	return vars["access_token"];
}

/+

void updateFbGraphPermissions(string token) {
	fbGraph([null, token], "/me/permissions", true, -1); // use the cache, but only read if it is in the future - basically, force a cache refresh
	fbGraph([null, token], "/me/friends", true, -1); // do the same thing for friends..
}

auto fbGraphPermissions(string token) {
	return fbGraph([null, token], "/me/permissions", true, 36); // use the cache
}

enum FacebookPermissions {
	user_likes,
	friends_likes,
	publish_stream,
	publish_actions,
	offline_access,
	manage_pages,
}

bool hasPermission(DataObject person, FacebookPermissions permission) {
	version(live) {} else return true; // on dev, just skip this stuff

	if(person.facebook_access_token.length == 0)
		return false;
	try {
		auto perms = getBasicDataFromVariant(fbGraphPermissions(person.                       facebook_access_token))[0];
		return (to!string(permission) in perms) ? true : false;
	} catch(FacebookApiException e) {
		return false; // the token doesn't work
	}

	return false;
}

+/


/****************************************/

//      Generic helper functions for web work

/****************************************/

import std.variant;
import std.json;

Variant jsonToVariant(string json) {
	auto decoded = parseJSON(json);
	return jsonValueToVariant(decoded);
}

Variant jsonValueToVariant(JSONValue v) {
	Variant ret;

	final switch(v.type) {
		case JSONType.string:
			ret = v.str;
		break;
		case JSONType.uinteger:
			ret = v.uinteger;
		break;
		case JSONType.integer:
			ret = v.integer;
		break;
		case JSONType.float_:
			ret = v.floating;
		break;
		case JSONType.object:
			Variant[string] obj;
			foreach(k, val; v.object) {
				obj[k] = jsonValueToVariant(val);
			}

			ret = obj;
		break;
		case JSONType.array:
			Variant[] arr;
			foreach(i; v.array) {
				arr ~= jsonValueToVariant(i);
			}

			ret = arr;
		break;
		case JSONType.true_:
			ret = true;
		break;
		case JSONType.false_:
			ret = false;
		break;
		case JSONType.null_:
			ret = null;
		break;
	}

	return ret;
}

/***************************************/

//       Interface to C lib for signing

/***************************************/

extern(C) {
	alias int hashid;
	MHASH mhash_hmac_init(hashid, const scope void*, int, int);
	bool mhash(const scope void*, const scope void*, int);
	int mhash_get_hash_pblock(hashid);
	byte* mhash_hmac_end(MHASH);
	int mhash_get_block_size(hashid);

	hashid MHASH_MD5 = 1;
	hashid MHASH_SHA1 = 2;
	hashid MHASH_SHA256 = 17;
	alias void* MHASH;
}

ubyte[] mhashSign(string data, string signWith, hashid algorithm) @trusted {
        auto td = mhash_hmac_init(algorithm, signWith.ptr, cast(int) signWith.length,
                            mhash_get_hash_pblock(algorithm));

        mhash(td, data.ptr, cast(int) data.length);
	auto mac = mhash_hmac_end(td);
	ubyte[] ret;

        for (int j = 0; j < mhash_get_block_size(algorithm); j++) {
                ret ~= cast(ubyte) mac[j];
        }

/*
	string ret;

        for (int j = 0; j < mhash_get_block_size(algorithm); j++) {
                ret ~= std.string.format("%.2x", mac[j]);
        }
*/

	return ret;
}

pragma(lib, "mhash");
