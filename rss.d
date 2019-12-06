/++
	RSS/Atom feed reading

	References:
	$(LIST
		* https://cyber.harvard.edu/rss/rss.html
		* http://www.rssboard.org/rss-specification
		* https://tools.ietf.org/html/rfc4287
		* https://en.wikipedia.org/wiki/Atom_(Web_standard)
	)
+/
module arsd.rss;

import arsd.dom;

/// generic subset of rss and atom, normalized for easy consumption
struct Feed {
	string title; ///
	string description; ///
	string lastUpdated; ///

	///
	static struct Item {
		string title; ///
		string link; ///
		string description; ///
		string author; ///
		string publicationDate; ///
		string lastUpdatedDate; ///
		string guid; ///

		string enclosureUri; ///
		string enclosureType; ///
		string enclosureSize; ///
	}

	Item[] items; ///
}

///
enum FeedType {
	unknown, ///
	rss, ///
	atom ///
}

///
FeedType identifyFeed(Element e) {
	assert(e !is null);

	if(e.tagName == "rss")
		return FeedType.rss;
	if(e.tagName == "feed" || e.tagName == "atom:feed")
		return FeedType.atom;

	return FeedType.unknown;
}

/// Parses a feed generically
Feed parseFeed(Element e) {
	final switch(identifyFeed(e)) {
		case FeedType.unknown:
			throw new Exception("Unknown feed type");
		case FeedType.rss:
			return parseRss(e).toGenericFeed();
		case FeedType.atom:
			return parseAtom(e).toGenericFeed();
	}
}

// application/rss+xml
// though some use text/rss+xml or application/rdf+xml

// root node of <rss version="whatever">

struct RssChannel {
	string title;
	string link;
	string description;
	string lastBuildDate; // last time content in here changed
	string pubDate; // format like "Sat, 07 Sep 2002 00:00:01 GMT" when it officially changes
	string docs; // idk?

	string cloud; // has domain, port, path, registerProcedure, protocol

	string language; // optional
	string copyright;
	string managingEditor;
	string webMaster;

	string category;

	string ttl; // in minutes, if present

	RssImage image;

	RssItem[] items;

	Feed toGenericFeed() {
		Feed f;
		f.title = this.title;
		f.description = this.description; // FIXME text vs html?
		f.lastUpdated = this.lastBuildDate; // FIXME: normalize format rss uses "Mon, 18 Nov 2019 12:00:00 GMT"

		foreach(item; items) {
			Feed.Item fi;

			fi.title = item.title;
			fi.link = item.link;
			fi.description = item.description; // FIXME: try to normalize text vs html
			fi.author = item.author; // FIXME
			fi.publicationDate = item.pubDate; // FIXME
			fi.guid = item.guid;
			//fi.lastUpdatedDate; // not available i think

			fi.enclosureUri = item.enclosure.url;
			fi.enclosureType = item.enclosure.type;
			fi.enclosureSize = item.enclosure.length;

			f.items ~= fi;
		}
		return f;
	}
}

struct RssImage {
	string title; /// img alt
	string url; /// like the img src
	string link; /// like a href
	string width;
	string height;
	string description; /// img title
}

struct RssItem {
	string title;
	string link;
	string description; // may have html!

	string author;
	string category;
	string comments; // a link

	string pubDate;
	string guid;

	RssSource source;
	RssEnclosure enclosure;
}

struct RssEnclosure {
	string url;
	string length;
	string type;
}

struct RssSource {
	string title;
	string url;
}


/++
	Parses RSS into structs. Requires the element to be RSS; if you are unsure
	of the type and want a generic response, use parseFeed instead.
+/
RssChannel parseRss(Element element) {
	assert(element !is null && element.tagName == "rss");
	RssChannel c;
	element = element.requireSelector(" > channel");
	foreach(memberName; __traits(allMembers, RssChannel)) {
		static if(memberName == "image") {
			if(auto image = element.querySelector(" > image")) {
				RssImage i;
				foreach(mn; __traits(allMembers, RssImage)) {
					__traits(getMember, i, mn) = image.optionSelector(" > " ~ mn).innerText;
				}
				c.image = i;
			}
		} else static if(memberName == "items") {
			foreach(item; element.querySelectorAll(" > item")) {
				RssItem i;
				foreach(mn; __traits(allMembers, RssItem)) {
					static if(mn == "source") {
						if(auto s = item.querySelector(" > source")) {
							i.source.title = s.innerText;
							i.source.url = s.attrs.url;
						}
					} else static if(mn == "enclosure") {
						if(auto s = item.querySelector(" > enclosure")) {
							i.enclosure.url = s.attrs.url;
							i.enclosure.type = s.attrs.type;
							i.enclosure.length = s.attrs.length;
						}
					} else {
						__traits(getMember, i, mn) = item.optionSelector(" > " ~ mn).innerText;
					}
				}
				c.items ~= i;
			}
		} else static if(is(typeof( __traits(getMember, c, memberName).offsetof))) {
			__traits(getMember, c, memberName) = element.optionSelector(" > " ~ memberName).innerText;
		}
	}

	return c;
}

///
RssChannel parseRss(string s) {
	auto document = new Document(s, true, true);
	return parseRss(document.root);
}

/*
struct SyndicationInfo {
	string updatePeriod; // sy:updatePeriod
	string updateFrequency;
	string updateBase;

	string skipHours; // stored as <hour> elements
	string skipDays; // stored as <day> elements
}
*/


// /////////////////// atom ////////////////////

// application/atom+xml

/+ rss vs atom
	date format is different
	atom:xxx links

	root node is <feed>, organization has no <channel>, and <entry>
	instead of <item>
+/

/++

+/
struct AtomFeed {
	string title; /// has a type attribute - text or html
	string subtitle; /// has a type attribute

	string updated; /// io string

	string id; ///
	string link; /// i want the text/html type really, certainly not rel=self
	string rights; ///
	string generator; ///

	AtomEntry[] entries; ///

	///
	Feed toGenericFeed() {
		Feed feed;

		feed.title = this.title;
		feed.description = this.subtitle;
		feed.lastUpdated = this.updated; // FIXME: normalize the format is 2005-07-31T12:29:29Z

		foreach(entry; this.entries) {
			Feed.Item item;

			item.title = entry.title;
			item.link = entry.link;
			item.description = entry.summary.html.length ? entry.summary.html : entry.summary.text; // FIXME
			item.author = entry.author.email; // FIXME normalize; RSS does "email (name)"
			item.publicationDate = entry.published; // FIXME the format is 2005-07-31T12:29:29Z
			item.lastUpdatedDate = entry.updated;
			item.guid = entry.id;

			item.enclosureUri = entry.enclosure.url;
			item.enclosureType = entry.enclosure.type;
			item.enclosureSize = entry.enclosure.length;

			feed.items ~= item;
		}

		return feed;
	}
}

///
struct AtomEntry {
	string title; ///
	string link; /// the alternate
	AtomEnclosure enclosure; ///
	string id; ///
	string updated; ///
	string published; ///

	AtomPerson author; ///
	AtomPerson[] contributors; ///
	AtomContent content; /// // should check type. may also have a src element for a link. type of html is escaped, type of xhtml is embedded.
	AtomContent summary; ///
}

///
struct AtomEnclosure {
	string url; ///
	string length; ///
	string type; ///
}


///
struct AtomContent {
	string text; ///
	string html; ///
}

///
struct AtomPerson {
	string name; ///
	string uri; ///
	string email; ///
}

///
AtomFeed parseAtom(Element ele) {
	AtomFeed af;
	af.title = ele.optionSelector(` > title, > atom\:title`).innerText;
	af.subtitle = ele.optionSelector(` > subtitle, > atom\:subtitle`).innerText;
	af.id = ele.optionSelector(` > id, > atom\:id`).innerText;
	af.updated = ele.optionSelector(` > updated, > atom\:updated`).innerText;
	af.rights = ele.optionSelector(` > rights, > atom\:rights`).innerText;
	af.generator = ele.optionSelector(` > generator, > atom\:generator`).innerText;
	af.link = ele.optionSelector(` > link:not([rel])`).getAttribute("href");

	foreach(entry; ele.querySelectorAll(` > entry`)) {
		AtomEntry ae;

		ae.title = entry.optionSelector(` > title, > atom\:title`).innerText;
		ae.updated = entry.optionSelector(` > updated, > atom\:updated`).innerText;
		ae.published = entry.optionSelector(` > published, > atom\:published`).innerText;
		ae.id = entry.optionSelector(` > id, > atom\:id`).innerText;

		ae.link = entry.optionSelector(` > link:not([rel]), > link[rel=alternate], > link[type="type/html"]`).getAttribute("href");

		if(auto enclosure = entry.querySelector(` > link[rel=enclosure]`)) {
			ae.enclosure.url = enclosure.attrs.href;
			ae.enclosure.length = enclosure.attrs.length;
			ae.enclosure.type = enclosure.attrs.type;
		}

		if(auto author = entry.querySelector(` > author`)) {
			ae.author.name = author.optionSelector(` > name`).innerText;
			ae.author.uri = author.optionSelector(` > uri`).innerText;
			ae.author.email = author.optionSelector(` > email`).innerText;
		}

		foreach(contributor; entry.querySelectorAll(` > contributor`)) {
			AtomPerson c;
			c.name = contributor.optionSelector(` > name`).innerText;
			c.uri = contributor.optionSelector(` > uri`).innerText;
			c.email = contributor.optionSelector(` > email`).innerText;
			ae.contributors ~= c;
		}

		if(auto e = entry.querySelector("content[type=xhtml]"))
			ae.content.html = e.innerHTML;
		if(auto e = entry.querySelector("content[type=html]"))
			ae.content.html = e.innerText;
		if(auto e = entry.querySelector("content[type=text], content:not([type])"))
			ae.content.text = e.innerText;

		if(auto e = entry.querySelector("summary[type=xhtml]"))
			ae.summary.html = e.innerHTML;
		if(auto e = entry.querySelector("summary[type=html]"))
			ae.summary.html = e.innerText;
		if(auto e = entry.querySelector("summary[type=text], summary:not([type])"))
			ae.summary.text = e.innerText;

		af.entries ~= ae;
	}

	return af;
}

AtomFeed parseAtom(string s) {
	auto document = new Document(s, true, true);
	return parseAtom(document.root);
}

unittest {

auto test1 = `<?xml version="1.0" encoding="ISO-8859-1"?>
<rss version="0.91">
	<channel>
		<title>WriteTheWeb</title> 
		<link>http://writetheweb.com</link> 
		<description>News for web users that write back</description> 
		<language>en-us</language> 
		<copyright>Copyright 2000, WriteTheWeb team.</copyright> 
		<managingEditor>editor@writetheweb.com</managingEditor> 
		<webMaster>webmaster@writetheweb.com</webMaster> 
		<image>
			<title>WriteTheWeb</title> 
			<url>http://writetheweb.com/images/mynetscape88.gif</url> 
			<link>http://writetheweb.com</link> 
			<width>88</width> 
			<height>31</height> 
			<description>News for web users that write back</description> 
			</image>
		<item>
			<title>Giving the world a pluggable Gnutella</title> 
			<link>http://writetheweb.com/read.php?item=24</link> 
			<description>WorldOS is a framework on which to build programs that work like Freenet or Gnutella -allowing distributed applications using peer-to-peer routing.</description> 
			</item>
		<item>
			<title>Syndication discussions hot up</title> 
			<link>http://writetheweb.com/read.php?item=23</link> 
			<description>After a period of dormancy, the Syndication mailing list has become active again, with contributions from leaders in traditional media and Web syndication.</description> 
			</item>
		<item>
			<title>Personal web server integrates file sharing and messaging</title> 
			<link>http://writetheweb.com/read.php?item=22</link> 
			<description>The Magi Project is an innovative project to create a combined personal web server and messaging system that enables the sharing and synchronization of information across desktop, laptop and palmtop devices.</description> 
			</item>
		<item>
			<title>Syndication and Metadata</title> 
			<link>http://writetheweb.com/read.php?item=21</link> 
			<description>RSS is probably the best known metadata format around. RDF is probably one of the least understood. In this essay, published on my O'Reilly Network weblog, I argue that the next generation of RSS should be based on RDF.</description> 
			</item>
		<item>
			<title>UK bloggers get organised</title> 
			<link>http://writetheweb.com/read.php?item=20</link> 
			<description>Looks like the weblogs scene is gathering pace beyond the shores of the US. There's now a UK-specific page on weblogs.com, and a mailing list at egroups.</description> 
			</item>
		<item>
			<title>Yournamehere.com more important than anything</title> 
			<link>http://writetheweb.com/read.php?item=19</link> 
			<description>Whatever you're publishing on the web, your site name is the most valuable asset you have, according to Carl Steadman.</description> 
			</item>
		</channel>
	</rss>`;


	{
		auto e = parseRss(test1);
		assert(e.items.length = 6);
		assert(e.items[$-1].title == "Yournamehere.com more important than anything", e.items[$-1].title);
		assert(e.items[0].title == "Giving the world a pluggable Gnutella");
		assert(e.image.url == "http://writetheweb.com/images/mynetscape88.gif");
	}

auto test2 = `<?xml version="1.0"?>
<!-- RSS generation done by 'Radio UserLand' on Fri, 13 Apr 2001 19:23:02 GMT -->
<rss version="0.92">
	<channel>
		<title>Dave Winer: Grateful Dead</title>
		<link>http://www.scripting.com/blog/categories/gratefulDead.html</link>
		<description>A high-fidelity Grateful Dead song every day. This is where we're experimenting with enclosures on RSS news items that download when you're not using your computer. If it works (it will) it will be the end of the Click-And-Wait multimedia experience on the Internet. </description>
		<lastBuildDate>Fri, 13 Apr 2001 19:23:02 GMT</lastBuildDate>
		<docs>http://backend.userland.com/rss092</docs>
		<managingEditor>dave@userland.com (Dave Winer)</managingEditor>
		<webMaster>dave@userland.com (Dave Winer)</webMaster>
		<cloud domain="data.ourfavoritesongs.com" port="80" path="/RPC2" registerProcedure="ourFavoriteSongs.rssPleaseNotify" protocol="xml-rpc"/>
		<item>
			<description>It's been a few days since I added a song to the Grateful Dead channel. Now that there are all these new Radio users, many of whom are tuned into this channel (it's #16 on the hotlist of upstreaming Radio users, there's no way of knowing how many non-upstreaming users are subscribing, have to do something about this..). Anyway, tonight's song is a live version of Weather Report Suite from Dick's Picks Volume 7. It's wistful music. Of course a beautiful song, oft-quoted here on Scripting News. &lt;i&gt;A little change, the wind and rain.&lt;/i&gt;
</description>
			<enclosure url="http://www.scripting.com/mp3s/weatherReportDicksPicsVol7.mp3" length="6182912" type="audio/mpeg"/>
			</item>
		<item>
			<description>Kevin Drennan started a &lt;a href="http://deadend.editthispage.com/"&gt;Grateful Dead Weblog&lt;/a&gt;. Hey it's cool, he even has a &lt;a href="http://deadend.editthispage.com/directory/61"&gt;directory&lt;/a&gt;. &lt;i&gt;A Frontier 7 feature.&lt;/i&gt;</description>
			<source url="http://scriptingnews.userland.com/xml/scriptingNews2.xml">Scripting News</source>
			</item>
		<item>
			<description>&lt;a href="http://arts.ucsc.edu/GDead/AGDL/other1.html"&gt;The Other One&lt;/a&gt;, live instrumental, One From The Vault. Very rhythmic very spacy, you can listen to it many times, and enjoy something new every time.</description>
			<enclosure url="http://www.scripting.com/mp3s/theOtherOne.mp3" length="6666097" type="audio/mpeg"/>
			</item>
		<item>
			<description>This is a test of a change I just made. Still diggin..</description>
			</item>
		<item>
			<description>The HTML rendering almost &lt;a href="http://validator.w3.org/check/referer"&gt;validates&lt;/a&gt;. Close. Hey I wonder if anyone has ever published a style guide for ALT attributes on images? What are you supposed to say in the ALT attribute? I sure don't know. If you're blind send me an email if u cn rd ths. </description>
			</item>
		<item>
			<description>&lt;a href="http://www.cs.cmu.edu/~mleone/gdead/dead-lyrics/Franklin's_Tower.txt"&gt;Franklin's Tower&lt;/a&gt;, a live version from One From The Vault.</description>
			<enclosure url="http://www.scripting.com/mp3s/franklinsTower.mp3" length="6701402" type="audio/mpeg"/>
			</item>
		<item>
			<description>Moshe Weitzman says Shakedown Street is what I'm lookin for for tonight. I'm listening right now. It's one of my favorites. "Don't tell me this town ain't got no heart." Too bright. I like the jazziness of Weather Report Suite. Dreamy and soft. How about The Other One? "Spanish lady come to me.."</description>
			<source url="http://scriptingnews.userland.com/xml/scriptingNews2.xml">Scripting News</source>
			</item>
		<item>
			<description>&lt;a href="http://www.scripting.com/mp3s/youWinAgain.mp3"&gt;The news is out&lt;/a&gt;, all over town..&lt;p&gt;
You've been seen, out runnin round. &lt;p&gt;
The lyrics are &lt;a href="http://www.cs.cmu.edu/~mleone/gdead/dead-lyrics/You_Win_Again.txt"&gt;here&lt;/a&gt;, short and sweet. &lt;p&gt;
&lt;i&gt;You win again!&lt;/i&gt;
</description>
			<enclosure url="http://www.scripting.com/mp3s/youWinAgain.mp3" length="3874816" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://www.getlyrics.com/lyrics/grateful-dead/wake-of-the-flood/07.htm"&gt;Weather Report Suite&lt;/a&gt;: "Winter rain, now tell me why, summers fade, and roses die? The answer came. The wind and rain. Golden hills, now veiled in grey, summer leaves have blown away. Now what remains? The wind and rain."</description>
			<enclosure url="http://www.scripting.com/mp3s/weatherReportSuite.mp3" length="12216320" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://arts.ucsc.edu/gdead/agdl/darkstar.html"&gt;Dark Star&lt;/a&gt; crashes, pouring its light into ashes.</description>
			<enclosure url="http://www.scripting.com/mp3s/darkStar.mp3" length="10889216" type="audio/mpeg"/>
			</item>
		<item>
			<description>DaveNet: &lt;a href="http://davenet.userland.com/2001/01/21/theUsBlues"&gt;The U.S. Blues&lt;/a&gt;.</description>
			</item>
		<item>
			<description>Still listening to the US Blues. &lt;i&gt;"Wave that flag, wave it wide and high.."&lt;/i&gt; Mistake made in the 60s. We gave our country to the assholes. Ah ah. Let's take it back. Hey I'm still a hippie. &lt;i&gt;"You could call this song The United States Blues."&lt;/i&gt;</description>
			</item>
		<item>
			<description>&lt;a href="http://www.sixties.com/html/garcia_stack_0.html"&gt;&lt;img src="http://www.scripting.com/images/captainTripsSmall.gif" height="51" width="42" border="0" hspace="10" vspace="10" align="right"&gt;&lt;/a&gt;In celebration of today's inauguration, after hearing all those great patriotic songs, America the Beautiful, even The Star Spangled Banner made my eyes mist up. It made my choice of Grateful Dead song of the night realllly easy. Here are the &lt;a href="http://searchlyrics2.homestead.com/gd_usblues.html"&gt;lyrics&lt;/a&gt;. Click on the audio icon to the left to give it a listen. "Red and white, blue suede shoes, I'm Uncle Sam, how do you do?" It's a different kind of patriotic music, but man I love my country and I love Jerry and the band. &lt;i&gt;I truly do!&lt;/i&gt;</description>
			<enclosure url="http://www.scripting.com/mp3s/usBlues.mp3" length="5272510" type="audio/mpeg"/>
			</item>
		<item>
			<description>Grateful Dead: "Tennessee, Tennessee, ain't no place I'd rather be."</description>
			<enclosure url="http://www.scripting.com/mp3s/tennesseeJed.mp3" length="3442648" type="audio/mpeg"/>
			</item>
		<item>
			<description>Ed Cone: "Had a nice Deadhead experience with my wife, who never was one but gets the vibe and knows and likes a lot of the music. Somehow she made it to the age of 40 without ever hearing Wharf Rat. We drove to Jersey and back over Christmas with the live album commonly known as Skull and Roses in the CD player much of the way, and it was cool to see her discover one the band's finest moments. That song is unique and underappreciated. Fun to hear that disc again after a few years off -- you get Jerry as blues-guitar hero on Big Railroad Blues and a nice version of Bertha."</description>
			<enclosure url="http://www.scripting.com/mp3s/darkStarWharfRat.mp3" length="27503386" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://arts.ucsc.edu/GDead/AGDL/fotd.html"&gt;Tonight's Song&lt;/a&gt;: "If I get home before daylight I just might get some sleep tonight." </description>
			<enclosure url="http://www.scripting.com/mp3s/friendOfTheDevil.mp3" length="3219742" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://arts.ucsc.edu/GDead/AGDL/uncle.html"&gt;Tonight's song&lt;/a&gt;: "Come hear Uncle John's Band by the river side. Got some things to talk about here beside the rising tide."</description>
			<enclosure url="http://www.scripting.com/mp3s/uncleJohnsBand.mp3" length="4587102" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://www.cs.cmu.edu/~mleone/gdead/dead-lyrics/Me_and_My_Uncle.txt"&gt;Me and My Uncle&lt;/a&gt;: "I loved my uncle, God rest his soul, taught me good, Lord, taught me all I know. Taught me so well, I grabbed that gold and I left his dead ass there by the side of the road."
</description>
			<enclosure url="http://www.scripting.com/mp3s/meAndMyUncle.mp3" length="2949248" type="audio/mpeg"/>
			</item>
		<item>
			<description>Truckin, like the doo-dah man, once told me gotta play your hand. Sometimes the cards ain't worth a dime, if you don't lay em down.</description>
			<enclosure url="http://www.scripting.com/mp3s/truckin.mp3" length="4847908" type="audio/mpeg"/>
			</item>
		<item>
			<description>Two-Way-Web: &lt;a href="http://www.thetwowayweb.com/payloadsForRss"&gt;Payloads for RSS&lt;/a&gt;. "When I started talking with Adam late last year, he wanted me to think about high quality video on the Internet, and I totally didn't want to hear about it."</description>
			</item>
		<item>
			<description>A touch of gray, kinda suits you anyway..</description>
			<enclosure url="http://www.scripting.com/mp3s/touchOfGrey.mp3" length="5588242" type="audio/mpeg"/>
			</item>
		<item>
			<description>&lt;a href="http://www.sixties.com/html/garcia_stack_0.html"&gt;&lt;img src="http://www.scripting.com/images/captainTripsSmall.gif" height="51" width="42" border="0" hspace="10" vspace="10" align="right"&gt;&lt;/a&gt;In celebration of today's inauguration, after hearing all those great patriotic songs, America the Beautiful, even The Star Spangled Banner made my eyes mist up. It made my choice of Grateful Dead song of the night realllly easy. Here are the &lt;a href="http://searchlyrics2.homestead.com/gd_usblues.html"&gt;lyrics&lt;/a&gt;. Click on the audio icon to the left to give it a listen. "Red and white, blue suede shoes, I'm Uncle Sam, how do you do?" It's a different kind of patriotic music, but man I love my country and I love Jerry and the band. &lt;i&gt;I truly do!&lt;/i&gt;</description>
			<enclosure url="http://www.scripting.com/mp3s/usBlues.mp3" length="5272510" type="audio/mpeg"/>
			</item>
		</channel>
	</rss><?xml version="1.0"?>`;

	{
		auto e = parseRss(test2);
		assert(e.items[$-1].enclosure.url == "http://www.scripting.com/mp3s/usBlues.mp3");
	}

auto test3 = `<rss version="2.0">
   <channel>
      <title>Liftoff News</title>
      <link>http://liftoff.msfc.nasa.gov/</link>
      <description>Liftoff to Space Exploration.</description>
      <language>en-us</language>
      <pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>
      <lastBuildDate>Tue, 10 Jun 2003 09:41:01 GMT</lastBuildDate>
      <docs>http://blogs.law.harvard.edu/tech/rss</docs>
      <generator>Weblog Editor 2.0</generator>
      <managingEditor>editor@example.com</managingEditor>
      <webMaster>webmaster@example.com</webMaster>
      <item>
         <title>Star City</title>
         <link>http://liftoff.msfc.nasa.gov/news/2003/news-starcity.asp</link>
         <description>How do Americans get ready to work with Russians aboard the International Space Station? They take a crash course in culture, language and protocol at Russia's &lt;a href="http://howe.iki.rssi.ru/GCTC/gctc_e.htm"&gt;Star City&lt;/a&gt;.</description>
         <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
         <guid>http://liftoff.msfc.nasa.gov/2003/06/03.html#item573</guid>
      </item>
      <item>
         <description>Sky watchers in Europe, Asia, and parts of Alaska and Canada will experience a &lt;a href="http://science.nasa.gov/headlines/y2003/30may_solareclipse.htm"&gt;partial eclipse of the Sun&lt;/a&gt; on Saturday, May 31st.</description>
         <pubDate>Fri, 30 May 2003 11:06:42 GMT</pubDate>
         <guid>http://liftoff.msfc.nasa.gov/2003/05/30.html#item572</guid>
      </item>
      <item>
         <title>The Engine That Does More</title>
         <link>http://liftoff.msfc.nasa.gov/news/2003/news-VASIMR.asp</link>
         <description>Before man travels to Mars, NASA hopes to design new engines that will let us fly through the Solar System more quickly.  The proposed VASIMR engine would do that.</description>
         <pubDate>Tue, 27 May 2003 08:37:32 GMT</pubDate>
         <guid>http://liftoff.msfc.nasa.gov/2003/05/27.html#item571</guid>
      </item>
      <item>
         <title>Astronauts' Dirty Laundry</title>
         <link>http://liftoff.msfc.nasa.gov/news/2003/news-laundry.asp</link>
         <description>Compared to earlier spacecraft, the International Space Station has many luxuries, but laundry facilities are not one of them.  Instead, astronauts have other options.</description>
         <pubDate>Tue, 20 May 2003 08:56:02 GMT</pubDate>
         <guid>http://liftoff.msfc.nasa.gov/2003/05/20.html#item570</guid>
      </item>
   </channel>
</rss>`;


auto testAtom1 = `<?xml version="1.0" encoding="utf-8"?>

<feed xmlns="http://www.w3.org/2005/Atom">

	<title>Example Feed</title>
	<subtitle>A subtitle.</subtitle>
	<link href="http://example.org/feed/" rel="self" />
	<link href="http://example.org/" />
	<id>urn:uuid:60a76c80-d399-11d9-b91C-0003939e0af6</id>
	<updated>2003-12-13T18:30:02Z</updated>
	
	
	<entry>
		<title>Atom-Powered Robots Run Amok</title>
		<link href="http://example.org/2003/12/13/atom03" />
		<link rel="alternate" type="text/html" href="http://example.org/2003/12/13/atom03.html"/>
		<link rel="edit" href="http://example.org/2003/12/13/atom03/edit"/>
		<id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
		<updated>2003-12-13T18:30:02Z</updated>
		<summary>Some text.</summary>
		<content type="xhtml">
			<div xmlns="http://www.w3.org/1999/xhtml">
				<p>This is the entry content.</p>
			</div>
		</content>
		<author>
			<name>John Doe</name>
			<email>johndoe@example.com</email>
		</author>
	</entry>

</feed>`;

	{
		auto e = parseAtom(testAtom1);

		assert(e.entries.length == 1);
		assert(e.link == "http://example.org/");
		assert(e.title == "Example Feed");
		assert(e.entries[0].title == "Atom-Powered Robots Run Amok");
		assert(e.entries[0].link == "http://example.org/2003/12/13/atom03", e.entries[0].link);
		assert(e.entries[0].summary.text == "Some text.", e.entries[0].summary.text);
		assert(e.entries[0].summary.html.length == 0);
		assert(e.entries[0].content.text.length == 0);
		assert(e.entries[0].content.html.length > 10);
	}

}
