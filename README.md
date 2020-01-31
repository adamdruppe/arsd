# About

This is a collection of modules that I've released over the years (the oldest module in here was originally written in 2006, pre-D1!) for a wide variety of purposes. Most of them stand alone, or have just one or two dependencies in here, so you don't have to download this whole repo. Feel free to email me, destructionator@gmail.com or ping me as `adam_d_ruppe` on the #d IRC channel if you want to ask me anything.

I'm always adding to it, but my policy on dependencies means you can ignore what you don't need. I am also committed to long-term support. Even the obsolete modules I haven't used for years I usually keep compiling at least, and the ones I do use I am very hesitant to break backward compatibility on. My semver increases are *very* conservative.

See the full list of (at least slightly) documented module here: http://arsd-official.dpldocs.info/arsd.html and refer to https://code.dlang.org/packages/arsd-official for the list of `dub`-enabled subpackages.

## Links

I have [a patreon](https://www.patreon.com/adam_d_ruppe) and my (almost) [weekly blog](http://dpldocs.info/this-week-in-d/) you can check out if you'd like to financially support this work or see the updates and tips I write about.

## Credits

Thanks go to Nick Sabalausky, Trass3r, Stanislav Blinov, ketmar, maartenvd, and many others over the years for input and patches.

Several of the modules are also ports of other C code, see the comments in those files for their original authors.

# Conventions

Many http-based functions in the lib also support unix sockets as an alternative to tcp.

With cgi.d, use

	--host unix:/path/here

or, on Linux:

	--host abstract:/path/here

after compiling with `-version=embedded_httpd_thread` to serve http on the given socket. (`abstract:` does a unix socket in the Linux-specific abstract namespace).

With http2.d, use

	Uri("http://whatever_host/path?args").viaUnixSocket("/path/here")

any time you are constructing a client. Note that `navigateTo` may lose the unix socket unless you specify it again.
