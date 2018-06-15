/// curl wrapper, it sux
module arsd.curl;

// see this for info on making a curl.lib on windows:
// http://stackoverflow.com/questions/7933845/where-is-curl-lib-for-dmd

pragma(lib, "curl");

import std.string;
extern(C) {
	struct CURL;
	struct curl_slist;

	alias int CURLcode;
	alias int CURLoption;

	enum int CURLOPT_URL = 10002;
	enum int CURLOPT_WRITEFUNCTION = 20011;
	enum int CURLOPT_WRITEDATA = 10001;
	enum int CURLOPT_POSTFIELDS = 10015;
	enum int CURLOPT_POSTFIELDSIZE = 60;
	enum int CURLOPT_POST = 47;
	enum int CURLOPT_HTTPHEADER = 10023;
	enum int CURLOPT_USERPWD = 0x00002715;

	enum int CURLOPT_VERBOSE = 41;

//	enum int CURLOPT_COOKIE = 22;
	enum int CURLOPT_COOKIEFILE = 10031;
	enum int CURLOPT_COOKIEJAR = 10082;

	enum int CURLOPT_SSL_VERIFYPEER = 64;

	enum int CURLOPT_FOLLOWLOCATION = 52;

	CURL* curl_easy_init();
	void curl_easy_cleanup(CURL* handle);
	CURLcode curl_easy_perform(CURL* curl);

	void curl_global_init(int flags);

	enum int CURL_GLOBAL_ALL = 0b1111;

	CURLcode curl_easy_setopt(CURL* handle, CURLoption option, ...);
	curl_slist* curl_slist_append(curl_slist*, const char*);
	void curl_slist_free_all(curl_slist*);

	// size is size of item, count is how many items
	size_t write_data(void* buffer, size_t size, size_t count, void* user) {
		string* str = cast(string*) user;
		char* data = cast(char*) buffer;

		assert(size == 1);

		*str ~= data[0..count];

		return count;
	}

	char* curl_easy_strerror(CURLcode  errornum );
}
/*
struct CurlOptions {
	string username;
	string password;
}
*/

string getDigestString(string s) {
	import std.digest.md;
	import std.digest.digest;
	auto hash = md5Of(s);
	auto a = toHexString(hash);
	return a.idup;
}
//import std.md5;
import std.file;
/// this automatically caches to a local file for the given time. it ignores the expires header in favor of your time to keep.
version(linux)
string cachedCurl(string url, int maxCacheHours) {
	string res;

	auto cacheFile = "/tmp/arsd-curl-cache-" ~ getDigestString(url);

	import std.datetime;

	if(!std.file.exists(cacheFile) || std.file.timeLastModified(cacheFile) < Clock.currTime() - dur!"hours"(maxCacheHours)) {
		res = curl(url);
		std.file.write(cacheFile, res);
	} else {
		res = cast(string) std.file.read(cacheFile);
	}

	return res;
}


string curl(string url, string data = null, string contentType = "application/x-www-form-urlencoded") {
	return curlAuth(url, data, null, null, contentType);
}

string curlCookie(string cookieFile, string url, string data = null, string contentType = "application/x-www-form-urlencoded") {
	return curlAuth(url, data, null, null, contentType, null, null, cookieFile);
}

string curlAuth(string url, string data = null, string username = null, string password = null, string contentType = "application/x-www-form-urlencoded", string methodOverride = null, string[] customHeaders = null, string cookieJar = null) {
	CURL* curl = curl_easy_init();
	if(curl is null)
		throw new Exception("curl init");
	scope(exit)
		curl_easy_cleanup(curl);

	string ret;

	int res;

	debug(arsd_curl_verbose)
		curl_easy_setopt(curl, CURLOPT_VERBOSE, 1);

	res = curl_easy_setopt(curl, CURLOPT_URL, std.string.toStringz(url));
	if(res != 0) throw new CurlException(res);
	if(username !is null) {
		res = curl_easy_setopt(curl, CURLOPT_USERPWD, std.string.toStringz(username ~ ":" ~ password));
		if(res != 0) throw new CurlException(res);
	}
	res = curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &write_data);
	if(res != 0) throw new CurlException(res);
	res = curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ret);
	if(res != 0) throw new CurlException(res);

	curl_slist* headers = null;
	//if(data !is null)
	//	contentType = "";
	if(contentType.length)
	headers = curl_slist_append(headers, toStringz("Content-Type: " ~ contentType));

	foreach(h; customHeaders) {
		headers = curl_slist_append(headers, toStringz(h));
	}
	scope(exit)
		curl_slist_free_all(headers);

	if(data) {
		res = curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data.ptr);
		if(res != 0) throw new CurlException(res);
		res = curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, data.length);
		if(res != 0) throw new CurlException(res);
	}

	res = curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	if(res != 0) throw new CurlException(res);

	if(cookieJar !is null) {
		res = curl_easy_setopt(curl, CURLOPT_COOKIEJAR, toStringz(cookieJar));
		if(res != 0) throw new CurlException(res);
		res = curl_easy_setopt(curl, CURLOPT_COOKIEFILE, toStringz(cookieJar));
		if(res != 0) throw new CurlException(res);
	} else {
		// just want to enable cookie parsing for location 3xx thingies.
		// some crappy sites will give you an endless runaround if they can't
		// place their fucking tracking cookies.
		res = curl_easy_setopt(curl, CURLOPT_COOKIEFILE, toStringz("lol totally not here"));
	}

	res = curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
	if(res != 0) throw new CurlException(res);
	//res = curl_easy_setopt(curl, 81, 0); // FIXME verify host
	//if(res != 0) throw new CurlException(res);

	version(no_curl_follow) {} else {
		res = curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1);
		if(res != 0) throw new CurlException(res);
	}

	if(methodOverride !is null) {
		switch(methodOverride) {
			default: assert(0);
			case "POST":
				res = curl_easy_setopt(curl, CURLOPT_POST, 1);
			break;
			case "GET":
				//curl_easy_setopt(curl, CURLOPT_POST, 0);
			break;
		}
	}

	auto failure = curl_easy_perform(curl);
	if(failure != 0)
		throw new CurlException(failure, "\nURL" ~ url);

	return ret;
}

class CurlException : Exception {
	this(CURLcode code, string msg = null, string file = __FILE__, int line = __LINE__) {
		string message = file ~ ":" ~ to!string(line) ~ " (" ~ to!string(code) ~ ") ";

		auto strerror = curl_easy_strerror(code);

		while(*strerror) {
			message ~= *strerror;
			strerror++;
		}

		super(message ~ msg);
	}
}


import std.conv;
