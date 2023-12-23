/++
	This package contains a variety of independent modules that I have
	written over my years of using D.

	You can usually use them independently, with few or no dependencies,
	so it is easy to use raw, or you can use dub packages as well.

	See [arsd.docs] for top-level documents in addition to what is below.

	What are you working with? (minimal starting points now but im working on it)

	${RAW_HTML
		<style>
			#table-of-contents, #details { display: none; }
			.category-grid {
				display: flex;
				flex-direction: row;
				flex-wrap: wrap;
				align-items: center;
				list-style-type: none;
			}
			.category-grid > * {
				flex-basis: 30%;
				min-width: 8em;
				background-color: #eee;
				color: black;
				margin: 6px;
				border-radius: 8px;
				border: solid 1px #ccc;
			}
			.category-grid > * > a:only-child {
				display: block;
				padding: 1em;
				padding-top: 3em;
				padding-bottom: 3em;
				box-sizing: border-box;
				height: 8em;
			}
			.category-grid a {
				color: inherit;
			}
		</style>
	}

	$(LIST
		$(CLASS category-grid)

		* [#web|Web]
		* [#desktop|Desktop]
		* [#terminals|Terminals]
		* [#databases|Databases]
		* [#scripting|Scripting]
		* [#email|Email]
	)


	$(H2 Categories)

	$(H3 Web)
		$(LIST
			$(CLASS category-grid)

			* [#web-server|Server-side code]
			* [#web-api-client|Consuming HTTP APIs]
			* [#web-scraper|Scraping Web Pages]
		)

		$(H4 $(ID web-server) Server-side code)
			See [arsd.cgi]

		$(H4 $(ID web-api-client) Consuming HTTP APIs)
			See [arsd.http2]

		$(H4 $(ID web-scraper) Scraping Web Pages)
			See [arsd.dom.Document.fromUrl]

	$(H3 Desktop)
		$(LIST
			$(CLASS category-grid)

			* [#desktop-game|Game]
			* [#desktop-gui|GUIs]
			* [#desktop-webview|WebView]
		)

		$(H4 $(ID desktop-game) Games)
			See [arsd.simpledisplay] and [arsd.gamehelpers].

			Check out [arsd.pixmappresenter] for old-skool games that blit fully-rendered frames to the screen.

		$(H4 $(ID desktop-gui) GUIs)
			See [arsd.minigui], [arsd.nanovega], and also: https://github.com/drug007/nanogui

			You can also do it yourself with [arsd.simpledisplay].

		$(H4 $(ID desktop-webview) WebView)
			This is a work in progress, but see [arsd.webview]
	$(H3 Terminals)
		$(LIST
			$(CLASS category-grid)

			* [#terminal-line|Line-based]
			* [#terminal-full|Full screen]
			* [#terminal-html|HTML dump]
		)

		$(H4 $(ID terminal-line) Line-based)
			See [arsd.terminal]

		$(H4 $(ID terminal-full) Full screen)
			See [arsd.terminal]

		$(H4 $(ID terminal-html) HTML dump)
			See [arsd.terminal] and [arsd.htmltotext]

	$(H3 Databases)
		$(LIST
			$(CLASS category-grid)

			* [#database-sql|SQL queries]
			* [#database-orm|Minimal ORM]
		)

		$(H4 $(ID database-sql) SQL queries)
			See [arsd.database], [arsd.mysql], [arsd.postgres], [arsd.sqlite], and [arsd.mssql].

		$(H4 $(ID database-orm) Minimal ORM)
			See [arsd.database_generation] as well as parts in [arsd.database].

	$(H3 Scripting)
		See [arsd.script]

	$(H3 Email)
		$(LIST
			$(CLASS category-grid)

			* [#email-sending|Sending Plain Email]
			* [#email-mime|Sending HTML Email]
			* [#email-processing|Processing Email]
		)

		$(H4 $(ID email-sending) Sending Plain Email)
			See [arsd.email]
		$(H4 $(ID email-mime) Sending HTML Email)
			See [arsd.email]
		$(H4 $(ID email-processing) Processing Email)
			See [arsd.email]
+/
module arsd;
