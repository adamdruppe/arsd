///
module arsd.hmac;

// FIXME: the blocksize is correct for MD5, SHA1, and SHA256 but not generally
// it should really be gotten from the hash
auto hmac(alias hash, size_t blocksize = 64)(in void[] keyv, in void[] messagev) {

	const(ubyte)[] key = cast(const(ubyte)[]) keyv;
	const(ubyte)[] message = cast(const(ubyte)[]) messagev;

	if(key.length > blocksize)
		key = hash(key);
	while(key.length < blocksize)
		key ~= 0;

	ubyte[blocksize] o_key_pad;
	ubyte[blocksize] i_key_pad;

	foreach(i; 0 .. blocksize) {
		o_key_pad[i] = 0x5c ^ key[i];
		i_key_pad[i] = 0x36 ^ key[i];
	}

	return hash(o_key_pad ~ hash(i_key_pad ~ message));
}

/*
unittest {
	import arsd.sha;
	import std.digest.md;
	import std.stdio;
	writeln(hashToString(hmac!md5Of("", ""))); // 0x74e6f7298a9c2d168935f58c001bad88


	writeln(hashToString(hmac!md5Of("key", "The quick brown fox jumps over the lazy dog"))); // 0x80070713463e7749b90c2dc24911e275
}
void main(){}
*/
