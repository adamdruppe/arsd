/++
	My minimal interface to https://github.com/p-h-c/phc-winner-argon2

	You must compile and install the C library separately.
+/
module arsd.argon2;

// a password length limitation might legit make sense here cuz of the hashing function can get slow

// it is conceivably useful to hash the password with a secret key before passing to this function,
// but I'm not going to do that automatically here just to keep this thin and simple.

import core.stdc.stdint;

pragma(lib, "argon2");

extern(C)
int argon2id_hash_encoded(
	const uint32_t t_cost,
        const uint32_t m_cost,
        const uint32_t parallelism,
        const void *pwd, const size_t pwdlen,
        const void *salt, const size_t saltlen,
        const size_t hashlen, char *encoded,
        const size_t encodedlen);

extern(C)
int argon2id_verify(const char *encoded, const void *pwd,
        const size_t pwdlen);

enum ARGON2_OK = 0;

/// Parameters to the argon2 function. Bigger numbers make it harder to
/// crack, but also take more resources for legitimate users too
/// (e.g. making logins and signups slower and more memory-intensive). Some
/// examples are provided. HighSecurity is about 3/4 second on my computer,
/// MediumSecurity about 1/3 second, LowSecurity about 1/10 second.
struct SecurityParameters {
	uint cpuCost;
	uint memoryCost; /// in KiB fyi
	uint parallelism;
}

/// ditto
enum HighSecurity = SecurityParameters(8, 512_000, 8);
/// ditto
enum MediumSecurity = SecurityParameters(4, 256_000, 4);
/// ditto
enum LowSecurity = SecurityParameters(2, 128_000, 4);

/// Check's a user's provided password against the saved password, and returns true if they matched. Neither string can be empty.
bool verify(string savedPassword, string providedPassword) {
	return argon2id_verify((savedPassword[$-1] == 0 ? savedPassword : (savedPassword ~ '\0')).ptr, providedPassword.ptr, providedPassword.length) == ARGON2_OK;
}

/// encode a password for secure storage. verify later with [verify]
string encode(string password, SecurityParameters params = MediumSecurity) {
	char[256] buffer;
	enum HASHLEN = 80;

	import core.stdc.string;

	ubyte[32] salt = void;

	version(linux) {{
		import core.sys.posix.unistd;
		import core.sys.posix.fcntl;
		int fd = open("/dev/urandom", O_RDONLY);
		auto ret = read(fd, salt.ptr, salt.length);
		assert(ret == salt.length);
		close(fd);
	}} else {
		import std.random;
		foreach(ref s; salt)
			s = cast(ubyte) uniform(0, 256);
	}

	auto ret = argon2id_hash_encoded(
		params.cpuCost,
		params.memoryCost,
		params.parallelism,
		password.ptr, password.length,
		salt.ptr, salt.length,
		HASHLEN, // desired size of hash. I think this is fine being arbitrary
		buffer.ptr,
		buffer.length
	);

	if(ret != ARGON2_OK)
		throw new Exception("wtf");

	return buffer[0 .. strlen(buffer.ptr) + 1].idup;
}
