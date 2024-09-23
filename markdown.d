/++

MD4C: Markdown parser for C
(http://github.com/mity/md4c)

Copyright:

Copyright (c) 2016-2019 Martin Mitas
Copyright (c) 2019 Guillaume Piolat (D translation as commonmarkd package: https://github.com/AuburnSounds/commonmark-d )
Somewhat modified by Adam D. Ruppe in 2024.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
+/
module arsd.markdown;

/// Options for Markdown parsing.
enum MarkdownFlag : int
{
     collapseWhitespace       = 0x0001,  /** Collapse non-trivial whitespace into single ' ' */
     permissiveATXHeaders     = 0x0002,  /** Do not require space in ATX headers ( ###header ) */
     permissiveURLAutoLinks   = 0x0004,  /** Recognize URLs as autolinks even without '<', '>' */
     permissiveEmailAutoLinks = 0x0008,  /** Recognize e-mails as autolinks even without '<', '>' and 'mailto:' */
     noIndentedCodeBlocks     = 0x0010,  /** Disable indented code blocks. (Only fenced code works.) */
     noHTMLBlocks             = 0x0020,  /** Disable raw HTML blocks. */
     noHTMLSpans              = 0x0040,  /** Disable raw HTML (inline). */
     tablesExtension          = 0x0100,  /** Enable tables extension. */
     enableStrikeThrough      = 0x0200,  /** Enable strikethrough extension. */
     permissiveWWWAutoLinks   = 0x0400,  /** Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.') */
     enableTaskLists          = 0x0800,  /** Enable task list extension. */
     latexMathSpans           = 0x1000,  /** Enable $ and $$ containing LaTeX equations. */

     permissiveAutoLinks      = permissiveEmailAutoLinks | permissiveURLAutoLinks | permissiveWWWAutoLinks, /** Recognize e-mails, URL and WWW links */
     noHTML                   = noHTMLBlocks | noHTMLSpans, /** Disable raw HTML. */

    /* Convenient sets of flags corresponding to well-known Markdown dialects.
     *
     * Note we may only support subset of features of the referred dialect.
     * The constant just enables those extensions which bring us as close as
     * possible given what features we implement.
     *
     * ABI compatibility note: Meaning of these can change in time as new
     * extensions, bringing the dialect closer to the original, are implemented.
     */
    dialectCommonMark          = 0, /** CommonMark */
    dialectGitHub              = (permissiveAutoLinks | tablesExtension | enableStrikeThrough | enableTaskLists), /** Github Flavoured Markdown */
}

/// Parses a Markdown input, returns HTML. `flags` set the particular Markdown dialect that is used.
string convertMarkdownToHTML(const(char)[] input, MarkdownFlag flags = MarkdownFlag.dialectCommonMark)
{
    import core.stdc.stdlib;

    static struct GrowableBuffer
    {
    nothrow:
    @nogc:
        char* buf = null;
        size_t size = 0;
        size_t allocated = 0;

        void ensureSize(size_t atLeastthisSize)
        {
            if (atLeastthisSize > allocated)
            {
                allocated = 2 * allocated + atLeastthisSize + 1; // TODO: enhancing this estimation probably beneficial to performance
                buf = cast(char*) realloc(buf, allocated);
            }

        }

        ~this()
        {
            if (buf)
            {
                free(buf);
                buf = null;
                size = 0;
                allocated = 0;
            }
        }

        void append(const(char)[] suffix)
        {
            size_t L = suffix.length;
            ensureSize(size + L);
            buf[size..size+L] = suffix[0..L];
            size += L;
        }

        const(char)[] getData()
        {
            return buf[0..size];
        }

        static void appendCallback(const(char)* chars, uint size, void* userData)
        {
            GrowableBuffer* gb = cast(GrowableBuffer*) userData;
            gb.append(chars[0..size]);
        }
    }

    GrowableBuffer gb;
    gb.ensureSize(input.length); // TODO: enhancing this estimation probably beneficial to performance

    //int renderFlags = MD_RENDER_FLAG_DEBUG;
    int renderFlags = 0;

    int ret = md_render_html(input.ptr,
                             cast(uint) input.length,
                             &GrowableBuffer.appendCallback,
                             &gb, flags, renderFlags);
    return gb.getData.idup; // Note: this is the only GC-using stuff
}




import core.stdc.string;
import core.stdc.stdio;
import core.stdc.stdlib: malloc, free;

nothrow:
@nogc:
@system:

// Compatibility with older DMDFE
static if (__VERSION__ < 2079)
{
    import core.stdc.stdlib: _compare_fp_t;
    // Provide @nogc nothrow bsearch and qsort for older compilers
    extern (C):
    @system:
    inout(void)* bsearch(scope const void* key, scope inout(void)* base, size_t nmemb, size_t size, _compare_fp_t compar);
    void    qsort(scope void* base, size_t nmemb, size_t size, _compare_fp_t compar);
}
else
{
    import core.stdc.stdlib: qsort, bsearch;
}

alias MD_CHAR = char;
alias MD_SIZE = uint;
alias MD_OFFSET = uint;

/* Block represents a part of document hierarchy structure like a paragraph
 * or list item.
 */
alias MD_BLOCKTYPE = int;
enum : MD_BLOCKTYPE
{
    /* <body>...</body> */
    MD_BLOCK_DOC = 0,

    /* <blockquote>...</blockquote> */
    MD_BLOCK_QUOTE,

    /* <ul>...</ul>
     * Detail: Structure MD_BLOCK_UL_DETAIL. */
    MD_BLOCK_UL,

    /* <ol>...</ol>
     * Detail: Structure MD_BLOCK_OL_DETAIL. */
    MD_BLOCK_OL,

    /* <li>...</li>
     * Detail: Structure MD_BLOCK_LI_DETAIL. */
    MD_BLOCK_LI,

    /* <hr> */
    MD_BLOCK_HR,

    /* <h1>...</h1> (for levels up to 6)
     * Detail: Structure MD_BLOCK_H_DETAIL. */
    MD_BLOCK_H,

    /* <pre><code>...</code></pre>
     * Note the text lines within code blocks are terminated with '\n'
     * instead of explicit MD_TEXT_BR. */
    MD_BLOCK_CODE,

    /* Raw HTML block. This itself does not correspond to any particular HTML
     * tag. The contents of it _is_ raw HTML source intended to be put
     * in verbatim form to the HTML output. */
    MD_BLOCK_HTML,

    /* <p>...</p> */
    MD_BLOCK_P,

    /* <table>...</table> and its contents.
     * Detail: Structure MD_BLOCK_TD_DETAIL (used with MD_BLOCK_TH and MD_BLOCK_TD)
     * Note all of these are used only if extension MD_FLAG_TABLES is enabled. */
    MD_BLOCK_TABLE,
    MD_BLOCK_THEAD,
    MD_BLOCK_TBODY,
    MD_BLOCK_TR,
    MD_BLOCK_TH,
    MD_BLOCK_TD
}

/* Span represents an in-line piece of a document which should be rendered with
 * the same font, color and other attributes. A sequence of spans forms a block
 * like paragraph or list item. */
alias MD_SPANTYPE = int;
enum : MD_SPANTYPE
{
    /* <em>...</em> */
    MD_SPAN_EM,

    /* <strong>...</strong> */
    MD_SPAN_STRONG,

    /* <a href="xxx">...</a>
     * Detail: Structure MD_SPAN_A_DETAIL. */
    MD_SPAN_A,

    /* <img src="xxx">...</a>
     * Detail: Structure MD_SPAN_IMG_DETAIL.
     * Note: Image text can contain nested spans and even nested images.
     * If rendered into ALT attribute of HTML <IMG> tag, it's responsibility
     * of the renderer to deal with it.
     */
    MD_SPAN_IMG,

    /* <code>...</code> */
    MD_SPAN_CODE,

    /* <del>...</del>
     * Note: Recognized only when MD_FLAG_STRIKETHROUGH is enabled.
     */
    MD_SPAN_DEL,

    /* For recognizing inline ($) and display ($$) equations
     * Note: Recognized only when MD_FLAG_LATEXMATHSPANS is enabled.
     */
    MD_SPAN_LATEXMATH,
    MD_SPAN_LATEXMATH_DISPLAY
}

/* Text is the actual textual contents of span. */
alias MD_TEXTTYPE = int;
enum : MD_TEXTTYPE
{
    /* Normal text. */
    MD_TEXT_NORMAL = 0,

    /* null character. CommonMark requires replacing null character with
     * the replacement char U+FFFD, so this allows caller to do that easily. */
    MD_TEXT_NULLCHAR,

    /* Line breaks.
     * Note these are not sent from blocks with verbatim output (MD_BLOCK_CODE
     * or MD_BLOCK_HTML). In such cases, '\n' is part of the text itself. */
    MD_TEXT_BR,         /* <br> (hard break) */
    MD_TEXT_SOFTBR,     /* '\n' in source text where it is not semantically meaningful (soft break) */

    /* Entity.
     * (a) Named entity, e.g. &nbsp;
     *     (Note MD4C does not have a list of known entities.
     *     Anything matching the regexp /&[A-Za-z][A-Za-z0-9]{1,47};/ is
     *     treated as a named entity.)
     * (b) Numerical entity, e.g. &#1234;
     * (c) Hexadecimal entity, e.g. &#x12AB;
     *
     * As MD4C is mostly encoding agnostic, application gets the verbatim
     * entity text into the MD_RENDERER::text_callback(). */
    MD_TEXT_ENTITY,

    /* Text in a code block (inside MD_BLOCK_CODE) or inlined code (`code`).
     * If it is inside MD_BLOCK_CODE, it includes spaces for indentation and
     * '\n' for new lines. MD_TEXT_BR and MD_TEXT_SOFTBR are not sent for this
     * kind of text. */
    MD_TEXT_CODE,

    /* Text is a raw HTML. If it is contents of a raw HTML block (i.e. not
     * an inline raw HTML), then MD_TEXT_BR and MD_TEXT_SOFTBR are not used.
     * The text contains verbatim '\n' for the new lines. */
    MD_TEXT_HTML,

    /* Text is inside an equation. This is processed the same way as inlined code
     * spans (`code`). */
    MD_TEXT_LATEXMATH
}


/* Alignment enumeration. */

alias MD_ALIGN = int;
enum : MD_ALIGN
{
    MD_ALIGN_DEFAULT = 0,   /* When unspecified. */
    MD_ALIGN_LEFT,
    MD_ALIGN_CENTER,
    MD_ALIGN_RIGHT
}


/* String attribute.
 *
 * This wraps strings which are outside of a normal text flow and which are
 * propagated within various detailed structures, but which still may contain
 * string portions of different types like e.g. entities.
 *
 * So, for example, lets consider an image has a title attribute string
 * set to "foo &quot; bar". (Note the string size is 14.)
 *
 * Then the attribute MD_SPAN_IMG_DETAIL::title shall provide the following:
 *  -- [0]: "foo "   (substr_types[0] == MD_TEXT_NORMAL; substr_offsets[0] == 0)
 *  -- [1]: "&quot;" (substr_types[1] == MD_TEXT_ENTITY; substr_offsets[1] == 4)
 *  -- [2]: " bar"   (substr_types[2] == MD_TEXT_NORMAL; substr_offsets[2] == 10)
 *  -- [3]: (n/a)    (n/a                              ; substr_offsets[3] == 14)
 *
 * Note that these conditions are guaranteed:
 *  -- substr_offsets[0] == 0
 *  -- substr_offsets[LAST+1] == size
 *  -- Only MD_TEXT_NORMAL, MD_TEXT_ENTITY, MD_TEXT_NULLCHAR substrings can appear.
 */
struct MD_ATTRIBUTE
{
    const (MD_CHAR)* text;
    MD_SIZE size;
    const (MD_TEXTTYPE)* substr_types;
    const (MD_OFFSET)* substr_offsets;
}


/* Detailed info for MD_BLOCK_UL. */
struct MD_BLOCK_UL_DETAIL
{
    int is_tight;           /* Non-zero if tight list, zero if loose. */
    MD_CHAR mark;           /* Item bullet character in MarkDown source of the list, e.g. '-', '+', '*'. */
}

/* Detailed info for MD_BLOCK_OL. */
struct MD_BLOCK_OL_DETAIL
{
    uint start;             /* Start index of the ordered list. */
    int is_tight;           /* Non-zero if tight list, zero if loose. */
    MD_CHAR mark_delimiter; /* Character delimiting the item marks in MarkDown source, e.g. '.' or ')' */
}

/* Detailed info for MD_BLOCK_LI. */
struct MD_BLOCK_LI_DETAIL
{
    int is_task;            /* Can be non-zero only with MD_FLAG_TASKLISTS */
    MD_CHAR task_mark;      /* If is_task, then one of 'x', 'X' or ' '. Undefined otherwise. */
    MD_OFFSET task_mark_offset;  /* If is_task, then offset in the input of the char between '[' and ']'. */
}

/* Detailed info for MD_BLOCK_H. */
struct MD_BLOCK_H_DETAIL
{
    uint level;         /* Header level (1 - 6) */
}

/* Detailed info for MD_BLOCK_CODE. */
struct MD_BLOCK_CODE_DETAIL
{
    MD_ATTRIBUTE info;
    MD_ATTRIBUTE lang;
    MD_CHAR fence_char;     /* The character used for fenced code block; or zero for indented code block. */
}

/* Detailed info for MD_BLOCK_TH and MD_BLOCK_TD. */
struct MD_BLOCK_TD_DETAIL
{
    MD_ALIGN align_;
}

/* Detailed info for MD_SPAN_A. */
struct MD_SPAN_A_DETAIL
{
    MD_ATTRIBUTE href;
    MD_ATTRIBUTE title;
}

/* Detailed info for MD_SPAN_IMG. */
struct MD_SPAN_IMG_DETAIL
{
    MD_ATTRIBUTE src;
    MD_ATTRIBUTE title;
}


/* Flags specifying extensions/deviations from CommonMark specification.
 *
 * By default (when MD_RENDERER::flags == 0), we follow CommonMark specification.
 * The following flags may allow some extensions or deviations from it.
 */
 enum
 {
     MD_FLAG_COLLAPSEWHITESPACE          = 0x0001,  /* In MD_TEXT_NORMAL, collapse non-trivial whitespace into single ' ' */
     MD_FLAG_PERMISSIVEATXHEADERS        = 0x0002,  /* Do not require space in ATX headers ( ###header ) */
     MD_FLAG_PERMISSIVEURLAUTOLINKS      = 0x0004,  /* Recognize URLs as autolinks even without '<', '>' */
     MD_FLAG_PERMISSIVEEMAILAUTOLINKS    = 0x0008,  /* Recognize e-mails as autolinks even without '<', '>' and 'mailto:' */
     MD_FLAG_NOINDENTEDCODEBLOCKS        = 0x0010,  /* Disable indented code blocks. (Only fenced code works.) */
     MD_FLAG_NOHTMLBLOCKS                = 0x0020,  /* Disable raw HTML blocks. */
     MD_FLAG_NOHTMLSPANS                 = 0x0040,  /* Disable raw HTML (inline). */
     MD_FLAG_TABLES                      = 0x0100,  /* Enable tables extension. */
     MD_FLAG_STRIKETHROUGH               = 0x0200,  /* Enable strikethrough extension. */
     MD_FLAG_PERMISSIVEWWWAUTOLINKS      = 0x0400,  /* Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.') */
     MD_FLAG_TASKLISTS                   = 0x0800,  /* Enable task list extension. */
     MD_FLAG_LATEXMATHSPANS              = 0x1000,  /* Enable $ and $$ containing LaTeX equations. */

     MD_FLAG_PERMISSIVEAUTOLINKS         = MD_FLAG_PERMISSIVEEMAILAUTOLINKS | MD_FLAG_PERMISSIVEURLAUTOLINKS | MD_FLAG_PERMISSIVEWWWAUTOLINKS,
     MD_FLAG_NOHTML                      = MD_FLAG_NOHTMLBLOCKS | MD_FLAG_NOHTMLSPANS,

    /* Convenient sets of flags corresponding to well-known Markdown dialects.
     *
     * Note we may only support subset of features of the referred dialect.
     * The constant just enables those extensions which bring us as close as
     * possible given what features we implement.
     *
     * ABI compatibility note: Meaning of these can change in time as new
     * extensions, bringing the dialect closer to the original, are implemented.
     */
    MD_DIALECT_COMMONMARK               = 0,
    MD_DIALECT_GITHUB                   = (MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_TABLES | MD_FLAG_STRIKETHROUGH | MD_FLAG_TASKLISTS),
}

/* Renderer structure.
 */
struct MD_PARSER
{
nothrow:
@nogc:
    /* Reserved. Set to zero.
     */
    uint abi_version;

    /* Dialect options. Bitmask of MD_FLAG_xxxx values.
     */
    uint flags;

    /* Caller-provided rendering callbacks.
     *
     * For some block/span types, more detailed information is provided in a
     * type-specific structure pointed by the argument 'detail'.
     *
     * The last argument of all callbacks, 'userdata', is just propagated from
     * md_parse() and is available for any use by the application.
     *
     * Note any strings provided to the callbacks as their arguments or as
     * members of any detail structure are generally not zero-terminated.
     * Application has take the respective size information into account.
     *
     * Callbacks may abort further parsing of the document by returning non-zero.
     */
    int function(MD_BLOCKTYPE /*type*/, void* /*detail*/, void* /*userdata*/) enter_block;
    int function(MD_BLOCKTYPE /*type*/, void* /*detail*/, void* /*userdata*/) leave_block;

    int function(MD_SPANTYPE /*type*/, void* /*detail*/, void* /*userdata*/) enter_span;
    int function(MD_SPANTYPE /*type*/, void* /*detail*/, void* /*userdata*/) leave_span;

    int function(MD_TEXTTYPE /*type*/, const(MD_CHAR)* /*text*/, MD_SIZE /*size*/, void* /*userdata*/) text;

    /* Debug callback. Optional (may be null).
     *
     * If provided and something goes wrong, this function gets called.
     * This is intended for debugging and problem diagnosis for developers;
     * it is not intended to provide any errors suitable for displaying to an
     * end user.
     */
    void function(const(char)* /*msg*/, void* /*userdata*/) debug_log;

    /* Reserved. Set to null.
     */
    void function() syntax;
}


/*****************************
 ***  Miscellaneous Stuff  ***
 *****************************/


/* Misc. macros. */

enum TRUE = 1;
enum FALSE = 0;


/************************
 ***  Internal Types  ***
 ************************/

/* These are omnipresent so lets save some typing. */
alias CHAR = MD_CHAR;
alias SZ = MD_SIZE;
alias OFF = MD_OFFSET;

/* During analyzes of inline marks, we need to manage some "mark chains",
 * of (yet unresolved) openers. This structure holds start/end of the chain.
 * The chain internals are then realized through MD_MARK::prev and ::next.
 */
struct MD_MARKCHAIN
{
    int head;   /* Index of first mark in the chain, or -1 if empty. */
    int tail;   /* Index of last mark in the chain, or -1 if empty. */
}

enum OPENERS_CHAIN_FIRST = 2;
enum OPENERS_CHAIN_LAST = 11;

/* Context propagated through all the parsing. */
struct MD_CTX
{
nothrow:
@nogc:

    /* Immutable stuff (parameters of md_parse()). */
    const(CHAR)* text;
    SZ size;
    MD_PARSER parser;
    void* userdata;

    /* When this is true, it allows some optimizations. */
    int doc_ends_with_newline;

    /* Helper temporary growing buffer. */
    CHAR* buffer;
    uint alloc_buffer;

    /* Reference definitions. */
    MD_REF_DEF* ref_defs;
    int n_ref_defs;
    int alloc_ref_defs;
    void** ref_def_hashtable;
    int ref_def_hashtable_size;

    /* Stack of inline/span markers.
     * This is only used for parsing a single block contents but by storing it
     * here we may reuse the stack for subsequent blocks; i.e. we have fewer
     * (re)allocations. */
    MD_MARK* marks;
    int n_marks;
    int alloc_marks;

    ubyte[256] mark_char_map;
    /* For resolving of inline spans. */
    MD_MARKCHAIN[12] mark_chains;

    MD_MARKCHAIN* PTR_CHAIN() return { return &mark_chains[0]; }
    MD_MARKCHAIN* TABLECELLBOUNDARIES() return { return &mark_chains[1]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_extraword_mod3_0() return { return &mark_chains[2]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_extraword_mod3_1() return { return &mark_chains[3]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_extraword_mod3_2() return { return &mark_chains[4]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_intraword_mod3_0() return { return &mark_chains[5]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_intraword_mod3_1() return { return &mark_chains[6]; }
    MD_MARKCHAIN* ASTERISK_OPENERS_intraword_mod3_2() return { return &mark_chains[7]; }
    MD_MARKCHAIN* UNDERSCORE_OPENERS() return { return &mark_chains[8]; }
    MD_MARKCHAIN* TILDE_OPENERS() return { return &mark_chains[9]; }
    MD_MARKCHAIN* BRACKET_OPENERS() return { return &mark_chains[10]; }
    MD_MARKCHAIN* DOLLAR_OPENERS() return { return &mark_chains[11]; }

    int n_table_cell_boundaries;

    /* For resolving links. */
    int unresolved_link_head;
    int unresolved_link_tail;

    /* For resolving raw HTML. */
    OFF html_comment_horizon;
    OFF html_proc_instr_horizon;
    OFF html_decl_horizon;
    OFF html_cdata_horizon;

    /* For block analysis.
     * Notes:
     *   -- It holds MD_BLOCK as well as MD_LINE structures. After each
     *      MD_BLOCK, its (multiple) MD_LINE(s) follow.
     *   -- For MD_BLOCK_HTML and MD_BLOCK_CODE, MD_VERBATIMLINE(s) are used
     *      instead of MD_LINE(s).
     */
    void* block_bytes;
    MD_BLOCK* current_block;
    int n_block_bytes;
    int alloc_block_bytes;

    /* For container block analysis. */
    MD_CONTAINER* containers;
    int n_containers;
    int alloc_containers;

    /* Minimal indentation to call the block "indented code block". */
    uint code_indent_offset;

    /* Contextual info for line analysis. */
    SZ code_fence_length;   /* For checking closing fence length. */
    int html_block_type;    /* For checking closing raw HTML condition. */
    int last_line_has_list_loosening_effect;
    int last_list_item_starts_with_two_blank_lines;

    void MD_LOG(const(char)* msg)
    {
        if(parser.debug_log != null)
            parser.debug_log(msg, userdata);
    }

    /* Character accessors. */
    CHAR CH(OFF off)
    {
        return text[off];
    }

    const(CHAR)* STR(OFF off)
    {
        return text + off;
    }

    bool ISANYOF(OFF off, const(CHAR)* palette) { return ISANYOF_(CH(off), palette); }
    bool ISANYOF2(OFF off, CHAR ch1, CHAR ch2)      { return ISANYOF2_(CH(off), ch1, ch2); }
    bool ISANYOF3(OFF off, CHAR ch1, CHAR ch2, CHAR ch3) { return ISANYOF3_(CH(off), ch1, ch2, ch3); }
    bool ISASCII(OFF off)                 { return ISASCII_(CH(off)); }
    bool ISBLANK(OFF off)                 { return ISBLANK_(CH(off)); }
    bool ISNEWLINE(OFF off)               { return ISNEWLINE_(CH(off)); }
    bool ISWHITESPACE(OFF off)            { return ISWHITESPACE_(CH(off)); }
    bool ISCNTRL(OFF off)                 { return ISCNTRL_(CH(off)); }
    bool ISPUNCT(OFF off)                 { return ISPUNCT_(CH(off)); }
    bool ISUPPER(OFF off)                 { return ISUPPER_(CH(off)); }
    bool ISLOWER(OFF off)                 { return ISLOWER_(CH(off)); }
    bool ISALPHA(OFF off)                 { return ISALPHA_(CH(off)); }
    bool ISDIGIT(OFF off)                 { return ISDIGIT_(CH(off)); }
    bool ISXDIGIT(OFF off)                { return ISXDIGIT_(CH(off)); }
    bool ISALNUM(OFF off)                 { return ISALNUM_(CH(off)); }
}

alias MD_LINETYPE = int;
enum : MD_LINETYPE
{
    MD_LINE_BLANK,
    MD_LINE_HR,
    MD_LINE_ATXHEADER,
    MD_LINE_SETEXTHEADER,
    MD_LINE_SETEXTUNDERLINE,
    MD_LINE_INDENTEDCODE,
    MD_LINE_FENCEDCODE,
    MD_LINE_HTML,
    MD_LINE_TEXT,
    MD_LINE_TABLE,
    MD_LINE_TABLEUNDERLINE
}

struct MD_LINE_ANALYSIS
{
nothrow:
@nogc:
    short type_;
    ushort data_;

    MD_LINETYPE type() const
    {
        return type_;
    }

    void type(MD_LINETYPE value)
    {
        type_ = cast(short)value;
    }

    int data() const
    {
        return data_;
    }

    void data(uint value)
    {
        data_ = cast(ushort)value;
    }

    OFF beg;
    OFF end;
    uint indent;        /* Indentation level. */
}

struct MD_LINE
{
    OFF beg;
    OFF end;
}

struct MD_VERBATIMLINE
{
    OFF beg;
    OFF end;
    OFF indent;
}


/*****************
 ***  Helpers  ***
 *****************/

pure
{
    /* Character classification.
     * Note we assume ASCII compatibility of code points < 128 here. */
    bool ISIN_(CHAR ch, CHAR ch_min, CHAR ch_max)
    {
        return (ch_min <= cast(uint)(ch) && cast(uint)(ch) <= ch_max);
    }

    bool ISANYOF_(CHAR ch, const(CHAR)* palette)
    {
        return md_strchr(palette, ch) != null;
    }

    bool ISANYOF2_(CHAR ch, CHAR ch1, CHAR ch2)
    {
        return (ch == ch1) || (ch == ch2);
    }

    bool ISANYOF3_(CHAR ch, CHAR ch1, CHAR ch2, CHAR ch3)
    {
        return (ch == ch1) || (ch == ch2) || (ch == ch3);
    }

    bool ISASCII_(CHAR ch)
    {
        return (cast(uint)ch) <= 127;
    }

    bool ISBLANK_(CHAR ch)
    {
        return ISANYOF2_(ch, ' ', '\t');
    }

    bool ISNEWLINE_(CHAR ch)
    {
        return ISANYOF2_(ch, '\r', '\n');
    }

    bool ISWHITESPACE_(CHAR ch)
    {
        return ISBLANK_(ch) || ISANYOF2_(ch, '\v', '\f');
    }

    bool ISCNTRL_(CHAR ch)
    {
        return (cast(uint)(ch) <= 31 || cast(uint)(ch) == 127);
    }

    bool ISPUNCT_(CHAR ch)
    {
        return ISIN_(ch, 33, 47) || ISIN_(ch, 58, 64) || ISIN_(ch, 91, 96) || ISIN_(ch, 123, 126);
    }

    bool ISUPPER_(CHAR ch)
    {
        return ISIN_(ch, 'A', 'Z');
    }

    bool ISLOWER_(CHAR ch)
    {
        return ISIN_(ch, 'a', 'z');
    }

    bool ISALPHA_(CHAR ch)
    {
        return ISUPPER_(ch) || ISLOWER_(ch);
    }

    bool ISDIGIT_(CHAR ch)
    {
        return ISIN_(ch, '0', '9');
    }

    bool ISXDIGIT_(CHAR ch)
    {
        return ISDIGIT_(ch) || ISIN_(ch, 'A', 'F') || ISIN_(ch, 'a', 'f');
    }

    bool ISALNUM_(CHAR ch)
    {
        return ISALPHA_(ch) || ISDIGIT_(ch);
    }
}

const(CHAR)* md_strchr(const(CHAR)* str, CHAR ch) pure
{
    OFF i;
    for(i = 0; str[i] != '\0'; i++) {
        if(ch == str[i])
            return (str + i);
    }
    return null;
}

/* Case insensitive check of string equality. */
int md_ascii_case_eq(const(CHAR)* s1, const(CHAR)* s2, SZ n)
{
    OFF i;
    for(i = 0; i < n; i++) {
        CHAR ch1 = s1[i];
        CHAR ch2 = s2[i];

        if(ISLOWER_(ch1))
            ch1 += ('A'-'a');
        if(ISLOWER_(ch2))
            ch2 += ('A'-'a');
        if(ch1 != ch2)
            return FALSE;
    }
    return TRUE;
}

int md_ascii_eq(const(CHAR)* s1, const(CHAR)* s2, SZ n)
{
    return memcmp(s1, s2, n * CHAR.sizeof) == 0;
}

int md_text_with_null_replacement(MD_CTX* ctx, MD_TEXTTYPE type, const(CHAR)* str, SZ size)
{
    OFF off = 0;
    int ret = 0;

    while(1) {
        while(off < size  &&  str[off] != '\0')
            off++;

        if(off > 0) {
            ret = ctx.parser.text(type, str, off, ctx.userdata);
            if(ret != 0)
                return ret;

            str += off;
            size -= off;
            off = 0;
        }

        if(off >= size)
            return 0;

        ret = ctx.parser.text(MD_TEXT_NULLCHAR, "", 1, ctx.userdata);
        if(ret != 0)
            return ret;
        off++;
    }
}

int MD_TEMP_BUFFER(MD_CTX* ctx, SZ sz)
{
    if(sz > ctx.alloc_buffer)
    {
        CHAR* new_buffer;
        SZ new_size = ((sz) + (sz) / 2 + 128) & ~127;
        new_buffer = cast(CHAR*) realloc_safe(ctx.buffer, new_size);
        if (new_buffer == null)
        {
            ctx.MD_LOG("realloc() failed.");
            return -1;
        }
        ctx.buffer = new_buffer;
        ctx.alloc_buffer = new_size;
    }
    return 0;
}

int MD_ENTER_BLOCK(MD_CTX* ctx, MD_BLOCKTYPE type, void* arg)
{
    int ret = ctx.parser.enter_block(type, arg, ctx.userdata);
    if(ret != 0)
    {
        ctx.MD_LOG("Aborted from enter_block() callback.");
        return ret;
    }
    return 0;
}

int MD_LEAVE_BLOCK(MD_CTX* ctx, MD_BLOCKTYPE type, void* arg)
{
    int ret = ctx.parser.leave_block(type, arg, ctx.userdata);
    if(ret != 0)
    {
        ctx.MD_LOG("Aborted from leave_block() callback.");
        return ret;
    }
    return 0;
}

int MD_ENTER_SPAN(MD_CTX* ctx, MD_SPANTYPE type, void* arg)
{
    int ret = ctx.parser.enter_span(type, arg, ctx.userdata);
    if(ret != 0)
    {
        ctx.MD_LOG("Aborted from enter_span() callback.");
        return ret;
    }
    return 0;
}

int MD_LEAVE_SPAN(MD_CTX* ctx, MD_SPANTYPE type, void* arg)
{
    int ret = ctx.parser.leave_span(type, arg, ctx.userdata);
    if(ret != 0)
    {
        ctx.MD_LOG("Aborted from leave_span() callback.");
        return ret;
    }
    return 0;
}

int MD_TEXT(MD_CTX* ctx, MD_TEXTTYPE type, const(MD_CHAR)* str, MD_SIZE size)
{
    if(size > 0)
    {
        int ret = ctx.parser.text((type), (str), (size), ctx.userdata);
        if (ret != 0)
        {
            ctx.MD_LOG("Aborted from text() callback.");
            return ret;
        }
    }
    return 0;
}

int MD_TEXT_INSECURE(MD_CTX* ctx, MD_TEXTTYPE type, const(MD_CHAR)* str, MD_SIZE size)
{
    if(size > 0)
    {
        int ret = md_text_with_null_replacement(ctx, type, str, size);
        if(ret != 0)
        {
            ctx.MD_LOG("Aborted from text() callback.");
            return ret;
        }
    }
    return 0;
}

/*************************
 ***  Unicode Support  ***
 *************************/

struct MD_UNICODE_FOLD_INFO
{
    uint[3] codepoints;
    int n_codepoints;
};



/* Binary search over sorted "map" of codepoints. Consecutive sequences
 * of codepoints may be encoded in the map by just using the
 * (MIN_CODEPOINT | 0x40000000) and (MAX_CODEPOINT | 0x80000000).
 *
 * Returns index of the found record in the map (in the case of ranges,
 * the minimal value is used); or -1 on failure. */
int md_unicode_bsearch__(uint codepoint, const(uint)* map, size_t map_size)
{
    int beg, end;
    int pivot_beg, pivot_end;

    beg = 0;
    end = cast(int) map_size-1;
    while(beg <= end) {
        /* Pivot may be a range, not just a single value. */
        pivot_beg = pivot_end = (beg + end) / 2;
        if(map[pivot_end] & 0x40000000)
            pivot_end++;
        if(map[pivot_beg] & 0x80000000)
            pivot_beg--;

        if(codepoint < (map[pivot_beg] & 0x00ffffff))
            end = pivot_beg - 1;
        else if(codepoint > (map[pivot_end] & 0x00ffffff))
            beg = pivot_end + 1;
        else
            return pivot_beg;
    }

    return -1;
}

bool md_is_unicode_whitespace__(uint codepoint)
{
    /* Unicode "Zs" category.
     * (generated by scripts/build_whitespace_map.py) */
    static immutable uint[] WHITESPACE_MAP =
    [
        0x0020, 0x00a0, 0x1680, 0x2000| 0x40000000, 0x200a | 0x80000000, 0x202f, 0x205f, 0x3000
    ];

    /* The ASCII ones are the most frequently used ones, also CommonMark
     * specification requests few more in this range. */
    if(codepoint <= 0x7f)
        return ISWHITESPACE_(cast(CHAR)codepoint);

    return (md_unicode_bsearch__(codepoint, WHITESPACE_MAP.ptr, WHITESPACE_MAP.length) >= 0);
}

bool md_is_unicode_punct__(uint codepoint)
{
    /* Unicode "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps" categories.
     * (generated by scripts/build_punct_map.py) */
    static immutable uint[] PUNCT_MAP =
    [
        0x0021 | 0x40000000,0x0023 | 0x80000000, 0x0025 | 0x40000000,0x002a | 0x80000000, 0x002c | 0x40000000,0x002f | 0x80000000, 0x003a | 0x40000000,0x003b | 0x80000000, 0x003f | 0x40000000,0x0040 | 0x80000000,
        0x005b | 0x40000000,0x005d | 0x80000000, 0x005f, 0x007b, 0x007d, 0x00a1, 0x00a7, 0x00ab, 0x00b6 | 0x40000000,0x00b7 | 0x80000000,
        0x00bb, 0x00bf, 0x037e, 0x0387, 0x055a | 0x40000000,0x055f | 0x80000000, 0x0589 | 0x40000000,0x058a | 0x80000000, 0x05be, 0x05c0,
        0x05c3, 0x05c6, 0x05f3 | 0x40000000,0x05f4 | 0x80000000, 0x0609 | 0x40000000,0x060a | 0x80000000, 0x060c | 0x40000000,0x060d | 0x80000000, 0x061b, 0x061e | 0x40000000,0x061f | 0x80000000,
        0x066a | 0x40000000,0x066d | 0x80000000, 0x06d4, 0x0700 | 0x40000000,0x070d | 0x80000000, 0x07f7 | 0x40000000,0x07f9 | 0x80000000, 0x0830 | 0x40000000,0x083e | 0x80000000, 0x085e,
        0x0964 | 0x40000000,0x0965 | 0x80000000, 0x0970, 0x09fd, 0x0a76, 0x0af0, 0x0c77, 0x0c84, 0x0df4, 0x0e4f,
        0x0e5a | 0x40000000,0x0e5b | 0x80000000, 0x0f04 | 0x40000000,0x0f12 | 0x80000000, 0x0f14, 0x0f3a | 0x40000000,0x0f3d | 0x80000000, 0x0f85, 0x0fd0 | 0x40000000,0x0fd4 | 0x80000000,
        0x0fd9 | 0x40000000,0x0fda | 0x80000000, 0x104a | 0x40000000,0x104f | 0x80000000, 0x10fb, 0x1360 | 0x40000000,0x1368 | 0x80000000, 0x1400, 0x166e, 0x169b | 0x40000000,0x169c | 0x80000000,
        0x16eb | 0x40000000,0x16ed | 0x80000000, 0x1735 | 0x40000000,0x1736 | 0x80000000, 0x17d4 | 0x40000000,0x17d6 | 0x80000000, 0x17d8 | 0x40000000,0x17da | 0x80000000, 0x1800 | 0x40000000,0x180a | 0x80000000,
        0x1944 | 0x40000000,0x1945 | 0x80000000, 0x1a1e | 0x40000000,0x1a1f | 0x80000000, 0x1aa0 | 0x40000000,0x1aa6 | 0x80000000, 0x1aa8 | 0x40000000,0x1aad | 0x80000000, 0x1b5a | 0x40000000,0x1b60 | 0x80000000,
        0x1bfc | 0x40000000,0x1bff | 0x80000000, 0x1c3b | 0x40000000,0x1c3f | 0x80000000, 0x1c7e | 0x40000000,0x1c7f | 0x80000000, 0x1cc0 | 0x40000000,0x1cc7 | 0x80000000, 0x1cd3, 0x2010 | 0x40000000,0x2027 | 0x80000000,
        0x2030 | 0x40000000,0x2043 | 0x80000000, 0x2045 | 0x40000000,0x2051 | 0x80000000, 0x2053 | 0x40000000,0x205e | 0x80000000, 0x207d | 0x40000000,0x207e | 0x80000000, 0x208d | 0x40000000,0x208e | 0x80000000,
        0x2308 | 0x40000000,0x230b | 0x80000000, 0x2329 | 0x40000000,0x232a | 0x80000000, 0x2768 | 0x40000000,0x2775 | 0x80000000, 0x27c5 | 0x40000000,0x27c6 | 0x80000000, 0x27e6 | 0x40000000,0x27ef | 0x80000000,
        0x2983 | 0x40000000,0x2998 | 0x80000000, 0x29d8 | 0x40000000,0x29db | 0x80000000, 0x29fc | 0x40000000,0x29fd | 0x80000000, 0x2cf9 | 0x40000000,0x2cfc | 0x80000000, 0x2cfe | 0x40000000,0x2cff | 0x80000000, 0x2d70,
        0x2e00 | 0x40000000,0x2e2e | 0x80000000, 0x2e30 | 0x40000000,0x2e4f | 0x80000000, 0x3001 | 0x40000000,0x3003 | 0x80000000, 0x3008 | 0x40000000,0x3011 | 0x80000000, 0x3014 | 0x40000000,0x301f | 0x80000000, 0x3030,
        0x303d, 0x30a0, 0x30fb, 0xa4fe | 0x40000000,0xa4ff | 0x80000000, 0xa60d | 0x40000000,0xa60f | 0x80000000, 0xa673, 0xa67e,
        0xa6f2 | 0x40000000,0xa6f7 | 0x80000000, 0xa874 | 0x40000000,0xa877 | 0x80000000, 0xa8ce | 0x40000000,0xa8cf | 0x80000000, 0xa8f8 | 0x40000000,0xa8fa | 0x80000000, 0xa8fc, 0xa92e | 0x40000000,0xa92f | 0x80000000,
        0xa95f, 0xa9c1 | 0x40000000,0xa9cd | 0x80000000, 0xa9de | 0x40000000,0xa9df | 0x80000000, 0xaa5c | 0x40000000,0xaa5f | 0x80000000, 0xaade | 0x40000000,0xaadf | 0x80000000, 0xaaf0 | 0x40000000,0xaaf1 | 0x80000000,
        0xabeb, 0xfd3e | 0x40000000,0xfd3f | 0x80000000, 0xfe10 | 0x40000000,0xfe19 | 0x80000000, 0xfe30 | 0x40000000,0xfe52 | 0x80000000, 0xfe54 | 0x40000000,0xfe61 | 0x80000000, 0xfe63, 0xfe68,
        0xfe6a | 0x40000000,0xfe6b | 0x80000000, 0xff01 | 0x40000000,0xff03 | 0x80000000, 0xff05 | 0x40000000,0xff0a | 0x80000000, 0xff0c | 0x40000000,0xff0f | 0x80000000, 0xff1a | 0x40000000,0xff1b | 0x80000000,
        0xff1f | 0x40000000,0xff20 | 0x80000000, 0xff3b | 0x40000000,0xff3d | 0x80000000, 0xff3f, 0xff5b, 0xff5d, 0xff5f | 0x40000000,0xff65 | 0x80000000, 0x10100 | 0x40000000,0x10102 | 0x80000000,
        0x1039f, 0x103d0, 0x1056f, 0x10857, 0x1091f, 0x1093f, 0x10a50 | 0x40000000,0x10a58 | 0x80000000, 0x10a7f,
        0x10af0 | 0x40000000,0x10af6 | 0x80000000, 0x10b39 | 0x40000000,0x10b3f | 0x80000000, 0x10b99 | 0x40000000,0x10b9c | 0x80000000, 0x10f55 | 0x40000000,0x10f59 | 0x80000000, 0x11047 | 0x40000000,0x1104d | 0x80000000,
        0x110bb | 0x40000000,0x110bc | 0x80000000, 0x110be | 0x40000000,0x110c1 | 0x80000000, 0x11140 | 0x40000000,0x11143 | 0x80000000, 0x11174 | 0x40000000,0x11175 | 0x80000000, 0x111c5 | 0x40000000,0x111c8 | 0x80000000,
        0x111cd, 0x111db, 0x111dd | 0x40000000,0x111df | 0x80000000, 0x11238 | 0x40000000,0x1123d | 0x80000000, 0x112a9, 0x1144b | 0x40000000,0x1144f | 0x80000000,
        0x1145b, 0x1145d, 0x114c6, 0x115c1 | 0x40000000,0x115d7 | 0x80000000, 0x11641 | 0x40000000,0x11643 | 0x80000000, 0x11660 | 0x40000000,0x1166c | 0x80000000,
        0x1173c | 0x40000000,0x1173e | 0x80000000, 0x1183b, 0x119e2, 0x11a3f | 0x40000000,0x11a46 | 0x80000000, 0x11a9a | 0x40000000,0x11a9c | 0x80000000, 0x11a9e | 0x40000000,0x11aa2 | 0x80000000,
        0x11c41 | 0x40000000,0x11c45 | 0x80000000, 0x11c70 | 0x40000000,0x11c71 | 0x80000000, 0x11ef7 | 0x40000000,0x11ef8 | 0x80000000, 0x11fff, 0x12470 | 0x40000000,0x12474 | 0x80000000,
        0x16a6e | 0x40000000,0x16a6f | 0x80000000, 0x16af5, 0x16b37 | 0x40000000,0x16b3b | 0x80000000, 0x16b44, 0x16e97 | 0x40000000,0x16e9a | 0x80000000, 0x16fe2,
        0x1bc9f, 0x1da87 | 0x40000000,0x1da8b | 0x80000000, 0x1e95e | 0x40000000,0x1e95f | 0x80000000
    ];

    /* The ASCII ones are the most frequently used ones, also CommonMark
     * specification requests few more in this range. */
    if(codepoint <= 0x7f)
        return ISPUNCT_(cast(CHAR)codepoint);

    return (md_unicode_bsearch__(codepoint, PUNCT_MAP.ptr, PUNCT_MAP.length) >= 0);
}

void md_get_unicode_fold_info(uint codepoint, MD_UNICODE_FOLD_INFO* info)
{
    /* Unicode "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps" categories.
     * (generated by scripts/build_punct_map.py) */
    static immutable uint[] FOLD_MAP_1 =
    [
        0x0041 | 0x40000000, 0x005a | 0x80000000, 0x00b5, 0x00c0 | 0x40000000, 0x00d6 | 0x80000000, 0x00d8 | 0x40000000, 0x00de | 0x80000000, 0x0100 | 0x40000000, 0x012e | 0x80000000, 0x0132 | 0x40000000, 0x0136 | 0x80000000,
        0x0139 | 0x40000000, 0x0147 | 0x80000000, 0x014a | 0x40000000, 0x0176 | 0x80000000, 0x0178, 0x0179 | 0x40000000, 0x017d | 0x80000000, 0x017f, 0x0181, 0x0182,
        0x0186, 0x0187, 0x0189, 0x018b, 0x018e, 0x018f, 0x0190, 0x0191, 0x0193,
        0x0194, 0x0196, 0x0197, 0x0198, 0x019c, 0x019d, 0x019f, 0x01a0 | 0x40000000, 0x01a4 | 0x80000000, 0x01a6,
        0x01a7, 0x01a9, 0x01ac, 0x01ae, 0x01af, 0x01b1, 0x01b3, 0x01b7, 0x01b8,
        0x01bc, 0x01c4, 0x01c5, 0x01c7, 0x01c8, 0x01ca, 0x01cb | 0x40000000, 0x01db | 0x80000000, 0x01de | 0x40000000, 0x01ee | 0x80000000,
        0x01f1, 0x01f2, 0x01f6, 0x01f7, 0x01f8 | 0x40000000, 0x021e | 0x80000000, 0x0220, 0x0222 | 0x40000000, 0x0232 | 0x80000000, 0x023a,
        0x023b, 0x023d, 0x023e, 0x0241, 0x0243, 0x0244, 0x0245, 0x0246 | 0x40000000, 0x024e | 0x80000000, 0x0345,
        0x0370, 0x0376, 0x037f, 0x0386, 0x0388 | 0x40000000, 0x038a | 0x80000000, 0x038c, 0x038e, 0x0391 | 0x40000000, 0x03a1 | 0x80000000,
        0x03a3 | 0x40000000, 0x03ab | 0x80000000, 0x03c2, 0x03cf, 0x03d0, 0x03d1, 0x03d5, 0x03d6, 0x03d8 | 0x40000000, 0x03ee | 0x80000000,
        0x03f0, 0x03f1, 0x03f4, 0x03f5, 0x03f7, 0x03f9, 0x03fa, 0x03fd | 0x40000000, 0x03ff | 0x80000000,
        0x0400 | 0x40000000, 0x040f | 0x80000000, 0x0410 | 0x40000000, 0x042f | 0x80000000, 0x0460 | 0x40000000, 0x0480 | 0x80000000, 0x048a | 0x40000000, 0x04be | 0x80000000, 0x04c0, 0x04c1 | 0x40000000, 0x04cd | 0x80000000,
        0x04d0 | 0x40000000, 0x052e | 0x80000000, 0x0531 | 0x40000000, 0x0556 | 0x80000000, 0x10a0 | 0x40000000, 0x10c5 | 0x80000000, 0x10c7, 0x10cd, 0x13f8 | 0x40000000, 0x13fd | 0x80000000, 0x1c80,
        0x1c81, 0x1c82, 0x1c83, 0x1c85, 0x1c86, 0x1c87, 0x1c88, 0x1c90 | 0x40000000, 0x1cba | 0x80000000,
        0x1cbd | 0x40000000, 0x1cbf | 0x80000000, 0x1e00 | 0x40000000, 0x1e94 | 0x80000000, 0x1e9b, 0x1ea0 | 0x40000000, 0x1efe | 0x80000000, 0x1f08 | 0x40000000, 0x1f0f | 0x80000000, 0x1f18 | 0x40000000, 0x1f1d | 0x80000000,
        0x1f28 | 0x40000000, 0x1f2f | 0x80000000, 0x1f38 | 0x40000000, 0x1f3f | 0x80000000, 0x1f48 | 0x40000000, 0x1f4d | 0x80000000, 0x1f59, 0x1f5b, 0x1f5d, 0x1f5f,
        0x1f68 | 0x40000000, 0x1f6f | 0x80000000, 0x1fb8, 0x1fba, 0x1fbe, 0x1fc8 | 0x40000000, 0x1fcb | 0x80000000, 0x1fd8, 0x1fda, 0x1fe8,
        0x1fea, 0x1fec, 0x1ff8, 0x1ffa, 0x2126, 0x212a, 0x212b, 0x2132, 0x2160 | 0x40000000, 0x216f | 0x80000000,
        0x2183, 0x24b6 | 0x40000000, 0x24cf | 0x80000000, 0x2c00 | 0x40000000, 0x2c2e | 0x80000000, 0x2c60, 0x2c62, 0x2c63, 0x2c64,
        0x2c67 | 0x40000000, 0x2c6b | 0x80000000, 0x2c6d, 0x2c6e, 0x2c6f, 0x2c70, 0x2c72, 0x2c75, 0x2c7e,
        0x2c80 | 0x40000000, 0x2ce2 | 0x80000000, 0x2ceb, 0x2cf2, 0xa640 | 0x40000000, 0xa66c | 0x80000000, 0xa680 | 0x40000000, 0xa69a | 0x80000000, 0xa722 | 0x40000000, 0xa72e | 0x80000000,
        0xa732 | 0x40000000, 0xa76e | 0x80000000, 0xa779, 0xa77d, 0xa77e | 0x40000000, 0xa786 | 0x80000000, 0xa78b, 0xa78d, 0xa790,
        0xa796 | 0x40000000, 0xa7a8 | 0x80000000, 0xa7aa, 0xa7ab, 0xa7ac, 0xa7ad, 0xa7ae, 0xa7b0, 0xa7b1, 0xa7b2,
        0xa7b3, 0xa7b4 | 0x40000000, 0xa7be | 0x80000000, 0xa7c2, 0xa7c4, 0xa7c5, 0xa7c6, 0xab70 | 0x40000000, 0xabbf | 0x80000000,
        0xff21 | 0x40000000, 0xff3a | 0x80000000, 0x10400 | 0x40000000, 0x10427 | 0x80000000, 0x104b0 | 0x40000000, 0x104d3 | 0x80000000, 0x10c80 | 0x40000000, 0x10cb2 | 0x80000000, 0x118a0 | 0x40000000, 0x118bf | 0x80000000,
        0x16e40 | 0x40000000, 0x16e5f | 0x80000000, 0x1e900 | 0x40000000, 0x1e921 | 0x80000000
    ];

    static immutable uint[] FOLD_MAP_1_DATA =
    [
        0x0061, 0x007a, 0x03bc, 0x00e0, 0x00f6, 0x00f8, 0x00fe, 0x0101, 0x012f, 0x0133, 0x0137, 0x013a, 0x0148,
        0x014b, 0x0177, 0x00ff, 0x017a, 0x017e, 0x0073, 0x0253, 0x0183, 0x0254, 0x0188, 0x0256, 0x018c, 0x01dd,
        0x0259, 0x025b, 0x0192, 0x0260, 0x0263, 0x0269, 0x0268, 0x0199, 0x026f, 0x0272, 0x0275, 0x01a1, 0x01a5,
        0x0280, 0x01a8, 0x0283, 0x01ad, 0x0288, 0x01b0, 0x028a, 0x01b4, 0x0292, 0x01b9, 0x01bd, 0x01c6, 0x01c6,
        0x01c9, 0x01c9, 0x01cc, 0x01cc, 0x01dc, 0x01df, 0x01ef, 0x01f3, 0x01f3, 0x0195, 0x01bf, 0x01f9, 0x021f,
        0x019e, 0x0223, 0x0233, 0x2c65, 0x023c, 0x019a, 0x2c66, 0x0242, 0x0180, 0x0289, 0x028c, 0x0247, 0x024f,
        0x03b9, 0x0371, 0x0377, 0x03f3, 0x03ac, 0x03ad, 0x03af, 0x03cc, 0x03cd, 0x03b1, 0x03c1, 0x03c3, 0x03cb,
        0x03c3, 0x03d7, 0x03b2, 0x03b8, 0x03c6, 0x03c0, 0x03d9, 0x03ef, 0x03ba, 0x03c1, 0x03b8, 0x03b5, 0x03f8,
        0x03f2, 0x03fb, 0x037b, 0x037d, 0x0450, 0x045f, 0x0430, 0x044f, 0x0461, 0x0481, 0x048b, 0x04bf, 0x04cf,
        0x04c2, 0x04ce, 0x04d1, 0x052f, 0x0561, 0x0586, 0x2d00, 0x2d25, 0x2d27, 0x2d2d, 0x13f0, 0x13f5, 0x0432,
        0x0434, 0x043e, 0x0441, 0x0442, 0x044a, 0x0463, 0xa64b, 0x10d0, 0x10fa, 0x10fd, 0x10ff, 0x1e01, 0x1e95,
        0x1e61, 0x1ea1, 0x1eff, 0x1f00, 0x1f07, 0x1f10, 0x1f15, 0x1f20, 0x1f27, 0x1f30, 0x1f37, 0x1f40, 0x1f45,
        0x1f51, 0x1f53, 0x1f55, 0x1f57, 0x1f60, 0x1f67, 0x1fb0, 0x1f70, 0x03b9, 0x1f72, 0x1f75, 0x1fd0, 0x1f76,
        0x1fe0, 0x1f7a, 0x1fe5, 0x1f78, 0x1f7c, 0x03c9, 0x006b, 0x00e5, 0x214e, 0x2170, 0x217f, 0x2184, 0x24d0,
        0x24e9, 0x2c30, 0x2c5e, 0x2c61, 0x026b, 0x1d7d, 0x027d, 0x2c68, 0x2c6c, 0x0251, 0x0271, 0x0250, 0x0252,
        0x2c73, 0x2c76, 0x023f, 0x2c81, 0x2ce3, 0x2cec, 0x2cf3, 0xa641, 0xa66d, 0xa681, 0xa69b, 0xa723, 0xa72f,
        0xa733, 0xa76f, 0xa77a, 0x1d79, 0xa77f, 0xa787, 0xa78c, 0x0265, 0xa791, 0xa797, 0xa7a9, 0x0266, 0x025c,
        0x0261, 0x026c, 0x026a, 0x029e, 0x0287, 0x029d, 0xab53, 0xa7b5, 0xa7bf, 0xa7c3, 0xa794, 0x0282, 0x1d8e,
        0x13a0, 0x13ef, 0xff41, 0xff5a, 0x10428, 0x1044f, 0x104d8, 0x104fb, 0x10cc0, 0x10cf2, 0x118c0, 0x118df,
        0x16e60, 0x16e7f, 0x1e922, 0x1e943
    ];

    static immutable uint[] FOLD_MAP_2 =
    [
        0x00df, 0x0130, 0x0149, 0x01f0, 0x0587, 0x1e96, 0x1e97, 0x1e98, 0x1e99,
        0x1e9a, 0x1e9e, 0x1f50, 0x1f80 | 0x40000000, 0x1f87 | 0x80000000, 0x1f88 | 0x40000000, 0x1f8f | 0x80000000, 0x1f90 | 0x40000000, 0x1f97 | 0x80000000, 0x1f98 | 0x40000000, 0x1f9f | 0x80000000,
        0x1fa0 | 0x40000000, 0x1fa7 | 0x80000000, 0x1fa8 | 0x40000000, 0x1faf | 0x80000000, 0x1fb2, 0x1fb3, 0x1fb4, 0x1fb6, 0x1fbc, 0x1fc2,
        0x1fc3, 0x1fc4, 0x1fc6, 0x1fcc, 0x1fd6, 0x1fe4, 0x1fe6, 0x1ff2, 0x1ff3,
        0x1ff4, 0x1ff6, 0x1ffc, 0xfb00, 0xfb01, 0xfb02, 0xfb05, 0xfb06, 0xfb13,
        0xfb14, 0xfb15, 0xfb16, 0xfb17
    ];

    static immutable uint[] FOLD_MAP_2_DATA =
    [
        0x0073,0x0073, 0x0069,0x0307, 0x02bc,0x006e, 0x006a,0x030c, 0x0565,0x0582, 0x0068,0x0331, 0x0074,0x0308,
        0x0077,0x030a, 0x0079,0x030a, 0x0061,0x02be, 0x0073,0x0073, 0x03c5,0x0313, 0x1f00,0x03b9, 0x1f07,0x03b9,
        0x1f00,0x03b9, 0x1f07,0x03b9, 0x1f20,0x03b9, 0x1f27,0x03b9, 0x1f20,0x03b9, 0x1f27,0x03b9, 0x1f60,0x03b9,
        0x1f67,0x03b9, 0x1f60,0x03b9, 0x1f67,0x03b9, 0x1f70,0x03b9, 0x03b1,0x03b9, 0x03ac,0x03b9, 0x03b1,0x0342,
        0x03b1,0x03b9, 0x1f74,0x03b9, 0x03b7,0x03b9, 0x03ae,0x03b9, 0x03b7,0x0342, 0x03b7,0x03b9, 0x03b9,0x0342,
        0x03c1,0x0313, 0x03c5,0x0342, 0x1f7c,0x03b9, 0x03c9,0x03b9, 0x03ce,0x03b9, 0x03c9,0x0342, 0x03c9,0x03b9,
        0x0066,0x0066, 0x0066,0x0069, 0x0066,0x006c, 0x0073,0x0074, 0x0073,0x0074, 0x0574,0x0576, 0x0574,0x0565,
        0x0574,0x056b, 0x057e,0x0576, 0x0574,0x056d
    ];

    static immutable uint[] FOLD_MAP_3 =
    [
        0x0390, 0x03b0, 0x1f52, 0x1f54, 0x1f56, 0x1fb7, 0x1fc7, 0x1fd2, 0x1fd3,
        0x1fd7, 0x1fe2, 0x1fe3, 0x1fe7, 0x1ff7, 0xfb03, 0xfb04
    ];

    static immutable uint[] FOLD_MAP_3_DATA =
    [
        0x03b9,0x0308,0x0301, 0x03c5,0x0308,0x0301, 0x03c5,0x0313,0x0300, 0x03c5,0x0313,0x0301,
        0x03c5,0x0313,0x0342, 0x03b1,0x0342,0x03b9, 0x03b7,0x0342,0x03b9, 0x03b9,0x0308,0x0300,
        0x03b9,0x0308,0x0301, 0x03b9,0x0308,0x0342, 0x03c5,0x0308,0x0300, 0x03c5,0x0308,0x0301,
        0x03c5,0x0308,0x0342, 0x03c9,0x0342,0x03b9, 0x0066,0x0066,0x0069, 0x0066,0x0066,0x006c
    ];

    static struct FOLD_MAP
    {
        const(uint)* map;
        const(uint)* data;
        size_t map_size;
        int n_codepoints;
    }

    /*static immutable*/ FOLD_MAP[3] FOLD_MAP_LIST =
    [
        FOLD_MAP(FOLD_MAP_1.ptr, FOLD_MAP_1_DATA.ptr, FOLD_MAP_1.length, 1),
        FOLD_MAP(FOLD_MAP_2.ptr, FOLD_MAP_2_DATA.ptr, FOLD_MAP_2.length, 2),
        FOLD_MAP(FOLD_MAP_3.ptr, FOLD_MAP_3_DATA.ptr, FOLD_MAP_3.length, 3),
    ];

    int i;

    /* Fast path for ASCII characters. */
    if(codepoint <= 0x7f) {
        info.codepoints[0] = codepoint;
        if(ISUPPER_(cast(CHAR)codepoint))
            info.codepoints[0] += 'a' - 'A';
        info.n_codepoints = 1;
        return;
    }

    /* Try to locate the codepoint in any of the maps. */
    for(i = 0; i < cast(int) (FOLD_MAP_LIST.length); i++) {
        int index;

        index = md_unicode_bsearch__(codepoint, FOLD_MAP_LIST[i].map, FOLD_MAP_LIST[i].map_size);
        if(index >= 0) {
            /* Found the mapping. */
            int n_codepoints = FOLD_MAP_LIST[i].n_codepoints;
            const uint* map = FOLD_MAP_LIST[i].map;
            const uint* codepoints = FOLD_MAP_LIST[i].data + (index * n_codepoints);

            memcpy(info.codepoints.ptr, codepoints, uint.sizeof * n_codepoints);
            info.n_codepoints = n_codepoints;

            if(FOLD_MAP_LIST[i].map[index] != codepoint) {
                /* The found mapping maps whole range of codepoints,
                 * i.e. we have to offset info.codepoints[0] accordingly. */
                if((map[index] & 0x00ffffff)+1 == codepoints[0]) {
                    /* Alternating type of the range. */
                    info.codepoints[0] = codepoint + ((codepoint & 0x1) == (map[index] & 0x1) ? 1 : 0);
                } else {
                    /* Range to range kind of mapping. */
                    info.codepoints[0] += (codepoint - (map[index] & 0x00ffffff));
                }
            }

            return;
        }
    }

    /* No mapping found. Map the codepoint to itself. */
    info.codepoints[0] = codepoint;
    info.n_codepoints = 1;
}


bool IS_UTF8_LEAD1(CHAR ch)
{
    return cast(ubyte)(ch) <= 0x7f;
}

bool IS_UTF8_LEAD2(CHAR ch)
{
    return (cast(ubyte)(ch) & 0xe0) == 0xc0;
}

bool IS_UTF8_LEAD3(CHAR ch)
{
    return (cast(ubyte)(ch) & 0xf0) == 0xe0;
}

bool IS_UTF8_LEAD4(CHAR ch)
{
    return (cast(ubyte)(ch) & 0xf8) == 0xf0;
}

bool IS_UTF8_TAIL(CHAR ch)
{
    return  (cast(ubyte)(ch) & 0xc0) == 0x80;
}

uint md_decode_utf8__(const(CHAR)* str, SZ str_size, SZ* p_size)
{
    if(!IS_UTF8_LEAD1(str[0])) {
        if(IS_UTF8_LEAD2(str[0])) {
            if(1 < str_size && IS_UTF8_TAIL(str[1])) {
                if(p_size != null)
                    *p_size = 2;

                return ((cast(uint)str[0] & 0x1f) << 6) |
                       ((cast(uint)str[1] & 0x3f) << 0);
            }
        } else if(IS_UTF8_LEAD3(str[0])) {
            if(2 < str_size && IS_UTF8_TAIL(str[1]) && IS_UTF8_TAIL(str[2])) {
                if(p_size != null)
                    *p_size = 3;

                return ((cast(uint)str[0] & 0x0f) << 12) |
                       ((cast(uint)str[1] & 0x3f) << 6) |
                       ((cast(uint)str[2] & 0x3f) << 0);
            }
        } else if(IS_UTF8_LEAD4(str[0])) {
            if(3 < str_size && IS_UTF8_TAIL(str[1]) && IS_UTF8_TAIL(str[2]) && IS_UTF8_TAIL(str[3])) {
                if(p_size != null)
                    *p_size = 4;

                return ((cast(uint)str[0] & 0x07) << 18) |
                       ((cast(uint)str[1] & 0x3f) << 12) |
                       ((cast(uint)str[2] & 0x3f) << 6) |
                       ((cast(uint)str[3] & 0x3f) << 0);
            }
        }
    }

    if(p_size != null)
        *p_size = 1;
    return cast(uint) str[0];
}

uint md_decode_utf8_before__(MD_CTX* ctx, OFF off)
{
    if(!IS_UTF8_LEAD1(ctx.CH(off-1))) {
        if(off > 1 && IS_UTF8_LEAD2(ctx.CH(off-2)) && IS_UTF8_TAIL(ctx.CH(off-1)))
            return ((cast(uint)ctx.CH(off-2) & 0x1f) << 6) |
                   ((cast(uint)ctx.CH(off-1) & 0x3f) << 0);

        if(off > 2 && IS_UTF8_LEAD3(ctx.CH(off-3)) && IS_UTF8_TAIL(ctx.CH(off-2)) && IS_UTF8_TAIL(ctx.CH(off-1)))
            return ((cast(uint)ctx.CH(off-3) & 0x0f) << 12) |
                   ((cast(uint)ctx.CH(off-2) & 0x3f) << 6) |
                   ((cast(uint)ctx.CH(off-1) & 0x3f) << 0);

        if(off > 3 && IS_UTF8_LEAD4(ctx.CH(off-4)) && IS_UTF8_TAIL(ctx.CH(off-3)) && IS_UTF8_TAIL(ctx.CH(off-2)) && IS_UTF8_TAIL(ctx.CH(off-1)))
            return ((cast(uint)ctx.CH(off-4) & 0x07) << 18) |
                   ((cast(uint)ctx.CH(off-3) & 0x3f) << 12) |
                   ((cast(uint)ctx.CH(off-2) & 0x3f) << 6) |
                   ((cast(uint)ctx.CH(off-1) & 0x3f) << 0);
    }

    return cast(uint) ctx.CH(off-1);
}

bool ISUNICODEWHITESPACE_(uint codepoint)
{
    return md_is_unicode_whitespace__(codepoint);
}

bool ISUNICODEWHITESPACE(MD_CTX* ctx, OFF off)
{
    return md_is_unicode_whitespace__(md_decode_utf8__(ctx.STR(off), ctx.size - (off), null));
}

bool ISUNICODEWHITESPACEBEFORE(MD_CTX* ctx, OFF off)
{
    return md_is_unicode_whitespace__(md_decode_utf8_before__(ctx, off));
}

bool ISUNICODEPUNCT(MD_CTX* ctx, OFF off)
{
    return md_is_unicode_punct__(md_decode_utf8__(ctx.STR(off), ctx.size - (off), null));
}

bool ISUNICODEPUNCTBEFORE(MD_CTX* ctx, OFF off)
{
    return md_is_unicode_punct__(md_decode_utf8_before__(ctx, off));
}

uint md_decode_unicode(const(CHAR)* str, OFF off, SZ str_size, SZ* p_char_size)
{
    return md_decode_utf8__(str+off, str_size-off, p_char_size);
}

/*************************************
 ***  Helper string manipulations  ***
 *************************************/

/* Fill buffer with copy of the string between 'beg' and 'end' but replace any
 * line breaks with given replacement character.
 *
 * NOTE: Caller is responsible to make sure the buffer is large enough.
 * (Given the output is always shorter then input, (end - beg) is good idea
 * what the caller should allocate.)
 */
void md_merge_lines(MD_CTX* ctx, OFF beg, OFF end, const(MD_LINE)* lines, int n_lines,
                    CHAR line_break_replacement_char, CHAR* buffer, SZ* p_size)
{
    CHAR* ptr = buffer;
    int line_index = 0;
    OFF off = beg;

    while(1) {
        const MD_LINE* line = &lines[line_index];
        OFF line_end = line.end;
        if(end < line_end)
            line_end = end;

        while(off < line_end) {
            *ptr = ctx.CH(off);
            ptr++;
            off++;
        }

        if(off >= end) {
            *p_size = cast(uint)(ptr - buffer);
            return;
        }

        *ptr = line_break_replacement_char;
        ptr++;

        line_index++;
        off = lines[line_index].beg;
    }
}

/* Wrapper of md_merge_lines() which allocates new buffer for the output string.
 */
int md_merge_lines_alloc(MD_CTX* ctx, OFF beg, OFF end, const(MD_LINE)* lines, int n_lines,
                         CHAR line_break_replacement_char, const(CHAR)** p_str, SZ* p_size)
{
    CHAR* buffer;

    buffer = cast(CHAR*) malloc(CHAR.sizeof * (end - beg));
    if(buffer == null) {
        ctx.MD_LOG("malloc() failed.");
        return -1;
    }

    md_merge_lines(ctx, beg, end, lines, n_lines,
                line_break_replacement_char, buffer, p_size);

    *p_str = buffer;
    return 0;
}

OFF md_skip_unicode_whitespace(const(CHAR)* label, OFF off, SZ size)
{
    SZ char_size;
    uint codepoint;

    while(off < size) {
        codepoint = md_decode_unicode(label, off, size, &char_size);
        if(!ISUNICODEWHITESPACE_(codepoint)  &&  !ISNEWLINE_(label[off]))
            break;
        off += char_size;
    }

    return off;
}


/******************************
 ***  Recognizing raw HTML  ***
 ******************************/

/* md_is_html_tag() may be called when processing inlines (inline raw HTML)
 * or when breaking document to blocks (checking for start of HTML block type 7).
 *
 * When breaking document to blocks, we do not yet know line boundaries, but
 * in that case the whole tag has to live on a single line. We distinguish this
 * by n_lines == 0.
 */
int md_is_html_tag(MD_CTX* ctx, const(MD_LINE)* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    int attr_state;
    OFF off = beg;
    OFF line_end = (n_lines > 0) ? lines[0].end : ctx.size;
    int i = 0;

    assert(ctx.CH(beg) == '<');

    if(off + 1 >= line_end)
        return FALSE;
    off++;

    /* For parsing attributes, we need a little state automaton below.
     * State -1: no attributes are allowed.
     * State 0: attribute could follow after some whitespace.
     * State 1: after a whitespace (attribute name may follow).
     * State 2: after attribute name ('=' MAY follow).
     * State 3: after '=' (value specification MUST follow).
     * State 41: in middle of unquoted attribute value.
     * State 42: in middle of single-quoted attribute value.
     * State 43: in middle of double-quoted attribute value.
     */
    attr_state = 0;

    if(ctx.CH(off) == '/') {
        /* Closer tag "</ ... >". No attributes may be present. */
        attr_state = -1;
        off++;
    }

    /* Tag name */
    if(off >= line_end  ||  !ctx.ISALPHA(off))
        return FALSE;
    off++;
    while(off < line_end  &&  (ctx.ISALNUM(off)  ||  ctx.CH(off) == '-'))
        off++;

    /* (Optional) attributes (if not closer), (optional) '/' (if not closer)
     * and final '>'. */
    while(1) {
        while(off < line_end  &&  !ctx.ISNEWLINE(off)) {
            if(attr_state > 40) {
                if(attr_state == 41 && (ctx.ISBLANK(off) || ctx.ISANYOF(off, "\"'=<>`"))) {
                    attr_state = 0;
                    off--;  /* Put the char back for re-inspection in the new state. */
                } else if(attr_state == 42 && ctx.CH(off) == '\'') {
                    attr_state = 0;
                } else if(attr_state == 43 && ctx.CH(off) == '"') {
                    attr_state = 0;
                }
                off++;
            } else if(ctx.ISWHITESPACE(off)) {
                if(attr_state == 0)
                    attr_state = 1;
                off++;
            } else if(attr_state <= 2 && ctx.CH(off) == '>') {
                /* End. */
                goto done;
            } else if(attr_state <= 2 && ctx.CH(off) == '/' && off+1 < line_end && ctx.CH(off+1) == '>') {
                /* End with digraph '/>' */
                off++;
                goto done;
            } else if((attr_state == 1 || attr_state == 2) && (ctx.ISALPHA(off) || ctx.CH(off) == '_' || ctx.CH(off) == ':')) {
                off++;
                /* Attribute name */
                while(off < line_end && (ctx.ISALNUM(off) || ctx.ISANYOF(off, "_.:-")))
                    off++;
                attr_state = 2;
            } else if(attr_state == 2 && ctx.CH(off) == '=') {
                /* Attribute assignment sign */
                off++;
                attr_state = 3;
            } else if(attr_state == 3) {
                /* Expecting start of attribute value. */
                if(ctx.CH(off) == '"')
                    attr_state = 43;
                else if(ctx.CH(off) == '\'')
                    attr_state = 42;
                else if(!ctx.ISANYOF(off, "\"'=<>`")  &&  !ctx.ISNEWLINE(off))
                    attr_state = 41;
                else
                    return FALSE;
                off++;
            } else {
                /* Anything unexpected. */
                return FALSE;
            }
        }

        /* We have to be on a single line. See definition of start condition
         * of HTML block, type 7. */
        if(n_lines == 0)
            return FALSE;

        i++;
        if(i >= n_lines)
            return FALSE;

        off = lines[i].beg;
        line_end = lines[i].end;

        if(attr_state == 0  ||  attr_state == 41)
            attr_state = 1;

        if(off >= max_end)
            return FALSE;
    }

done:
    if(off >= max_end)
        return FALSE;

    *p_end = off+1;
    return TRUE;
}

static int
md_scan_for_html_closer(MD_CTX* ctx, const MD_CHAR* str, MD_SIZE len,
                        const MD_LINE* lines, int n_lines,
                        OFF beg, OFF max_end, OFF* p_end,
                        OFF* p_scan_horizon)
{
    OFF off = beg;
    int i = 0;

    if(off < *p_scan_horizon  &&  *p_scan_horizon >= max_end - len) {
        /* We have already scanned the range up to the max_end so we know
         * there is nothing to see. */
        return FALSE;
    }

    while(TRUE) {
        while(off + len <= lines[i].end  &&  off + len <= max_end) {
            if(md_ascii_eq(ctx.STR(off), str, len)) {
                /* Success. */
                *p_end = off + len;
                return TRUE;
            }
            off++;
        }

        i++;
        if(off >= max_end  ||  i >= n_lines) {
            /* Failure. */
            *p_scan_horizon = off;
            return FALSE;
        }

        off = lines[i].beg;
    }
}

static int
md_is_html_comment(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    assert(ctx.CH(beg) == '<');

    if(off + 4 >= lines[0].end)
        return FALSE;
    if(ctx.CH(off+1) != '!'  ||  ctx.CH(off+2) != '-'  ||  ctx.CH(off+3) != '-')
        return FALSE;
    off += 4;

    /* ">" and "." must not follow the opening. */
    if(off < lines[0].end  &&  ctx.CH(off) == '>')
        return FALSE;
    if(off+1 < lines[0].end  &&  ctx.CH(off) == '-'  &&  ctx.CH(off+1) == '>')
        return FALSE;

    /* HTML comment must not contain "--", so we scan just for "--" instead
     * of "-." and verify manually that '>' follows. */
    if(md_scan_for_html_closer(ctx, "--", 2,
                lines, n_lines, off, max_end, p_end, &ctx.html_comment_horizon))
    {
        if(*p_end < max_end  &&  ctx.CH(*p_end) == '>') {
            *p_end = *p_end + 1;
            return TRUE;
        }
    }

    return FALSE;
}

static int
md_is_html_processing_instruction(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    if(off + 2 >= lines[0].end)
        return FALSE;
    if(ctx.CH(off+1) != '?')
        return FALSE;
    off += 2;

    return md_scan_for_html_closer(ctx, "?>", 2,
                lines, n_lines, off, max_end, p_end, &ctx.html_proc_instr_horizon);
}

static int
md_is_html_declaration(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    if(off + 2 >= lines[0].end)
        return FALSE;
    if(ctx.CH(off+1) != '!')
        return FALSE;
    off += 2;

    /* Declaration name. */
    if(off >= lines[0].end  ||  !ctx.ISALPHA(off))
        return FALSE;
    off++;
    while(off < lines[0].end  &&  ctx.ISALPHA(off))
        off++;
    if(off < lines[0].end  &&  !ctx.ISWHITESPACE(off))
        return FALSE;

    return md_scan_for_html_closer(ctx, ">", 1,
                lines, n_lines, off, max_end, p_end, &ctx.html_decl_horizon);
}

static int
md_is_html_cdata(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    string open_str = "<![CDATA[";

    OFF off = beg;

    if(off + open_str.length >= lines[0].end)
        return FALSE;
    if(memcmp(ctx.STR(off), open_str.ptr, open_str.length) != 0)
        return FALSE;
    off += open_str.length;

    if(lines[n_lines-1].end < max_end)
        max_end = lines[n_lines-1].end - 2;

    return md_scan_for_html_closer(ctx, "]]>", 3,
                lines, n_lines, off, max_end, p_end, &ctx.html_cdata_horizon);
}

static int
md_is_html_any(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg, OFF max_end, OFF* p_end)
{
    assert(ctx.CH(beg) == '<');
    return (md_is_html_tag(ctx, lines, n_lines, beg, max_end, p_end)  ||
            md_is_html_comment(ctx, lines, n_lines, beg, max_end, p_end)  ||
            md_is_html_processing_instruction(ctx, lines, n_lines, beg, max_end, p_end)  ||
            md_is_html_declaration(ctx, lines, n_lines, beg, max_end, p_end)  ||
            md_is_html_cdata(ctx, lines, n_lines, beg, max_end, p_end));
}


/****************************
 ***  Recognizing Entity  ***
 ****************************/

static int
md_is_hex_entity_contents(MD_CTX* ctx, const(CHAR)* text, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    while(off < max_end  &&  ISXDIGIT_(text[off])  &&  off - beg <= 8)
        off++;

    if(1 <= off - beg  &&  off - beg <= 6) {
        *p_end = off;
        return TRUE;
    } else {
        return FALSE;
    }
}

static int
md_is_dec_entity_contents(MD_CTX* ctx, const(CHAR)* text, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    while(off < max_end  &&  ISDIGIT_(text[off])  &&  off - beg <= 8)
        off++;

    if(1 <= off - beg  &&  off - beg <= 7) {
        *p_end = off;
        return TRUE;
    } else {
        return FALSE;
    }
}

static int
md_is_named_entity_contents(MD_CTX* ctx, const(CHAR)* text, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg;

    if(off < max_end  &&  ISALPHA_(text[off]))
        off++;
    else
        return FALSE;

    while(off < max_end  &&  ISALNUM_(text[off])  &&  off - beg <= 48)
        off++;

    if(2 <= off - beg  &&  off - beg <= 48) {
        *p_end = off;
        return TRUE;
    } else {
        return FALSE;
    }
}

static int
md_is_entity_str(MD_CTX* ctx, const(CHAR)* text, OFF beg, OFF max_end, OFF* p_end)
{
    int is_contents;
    OFF off = beg;

    assert(text[off] == '&');
    off++;

    if(off+2 < max_end  &&  text[off] == '#'  &&  (text[off+1] == 'x' || text[off+1] == 'X'))
        is_contents = md_is_hex_entity_contents(ctx, text, off+2, max_end, &off);
    else if(off+1 < max_end  &&  text[off] == '#')
        is_contents = md_is_dec_entity_contents(ctx, text, off+1, max_end, &off);
    else
        is_contents = md_is_named_entity_contents(ctx, text, off, max_end, &off);

    if(is_contents  &&  off < max_end  &&  text[off] == ';') {
        *p_end = off+1;
        return TRUE;
    } else {
        return FALSE;
    }
}

static int
md_is_entity(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end)
{
    return md_is_entity_str(ctx, ctx.text, beg, max_end, p_end);
}


/******************************
 ***  Attribute Management  ***
 ******************************/

struct MD_ATTRIBUTE_BUILD
{
    CHAR* text = null;
    MD_TEXTTYPE* substr_types = null;
    OFF* substr_offsets = null;
    int substr_count = 0;
    int substr_alloc = 0;
    MD_TEXTTYPE[1] trivial_types = [0];
    OFF[2] trivial_offsets = [0, 0];
}


enum MD_BUILD_ATTR_NO_ESCAPES = 0x0001;

void* realloc_safe(void* ptr, size_t newSize)
{
    import core.stdc.stdlib : free, realloc;

    if (newSize == 0)
    {
        free(ptr);
        return null;
    }

    return realloc(ptr, newSize);
}


int md_build_attr_append_substr(MD_CTX* ctx, MD_ATTRIBUTE_BUILD* build,
                                MD_TEXTTYPE type, OFF off)
{
    if(build.substr_count >= build.substr_alloc) {
        MD_TEXTTYPE* new_substr_types;
        OFF* new_substr_offsets;

        build.substr_alloc = (build.substr_alloc == 0 ? 8 : build.substr_alloc * 2);

        new_substr_types = cast(MD_TEXTTYPE*) realloc_safe(build.substr_types,
                                    build.substr_alloc * MD_TEXTTYPE.sizeof);
        if(new_substr_types == null) {
            ctx.MD_LOG("realloc() failed.");
            return -1;
        }
        /* Note +1 to reserve space for final offset (== raw_size). */
        new_substr_offsets = cast(OFF*) realloc_safe(build.substr_offsets,
                                    (build.substr_alloc+1) * OFF.sizeof);
        if(new_substr_offsets == null) {
            ctx.MD_LOG("realloc() failed.");
            free(new_substr_types);
            return -1;
        }

        build.substr_types = new_substr_types;
        build.substr_offsets = new_substr_offsets;
    }

    build.substr_types[build.substr_count] = type;
    build.substr_offsets[build.substr_count] = off;
    build.substr_count++;
    return 0;
}

void md_free_attribute(MD_CTX* ctx, MD_ATTRIBUTE_BUILD* build)
{
    if(build.substr_alloc > 0) {
        free(build.text);
        free(build.substr_types);
        free(build.substr_offsets);
    }
}

int md_build_attribute(MD_CTX* ctx, const(CHAR)* raw_text, SZ raw_size,
                       uint flags, MD_ATTRIBUTE* attr, MD_ATTRIBUTE_BUILD* build)
{
    OFF raw_off, off;
    int is_trivial;
    int ret = 0;

    memset(build, 0, MD_ATTRIBUTE_BUILD.sizeof);

    /* If there is no backslash and no ampersand, build trivial attribute
     * without any malloc(). */
    is_trivial = TRUE;
    for(raw_off = 0; raw_off < raw_size; raw_off++) {
        if(ISANYOF3_(raw_text[raw_off], '\\', '&', '\0')) {
            is_trivial = FALSE;
            break;
        }
    }

    if(is_trivial) {
        build.text = cast(CHAR*) (raw_size ? raw_text : null);
        build.substr_types = build.trivial_types.ptr;
        build.substr_offsets = build.trivial_offsets.ptr;
        build.substr_count = 1;
        build.substr_alloc = 0;
        build.trivial_types[0] = MD_TEXT_NORMAL;
        build.trivial_offsets[0] = 0;
        build.trivial_offsets[1] = raw_size;
        off = raw_size;
    } else {
        build.text = cast(CHAR*) malloc(raw_size * CHAR.sizeof);
        if(build.text == null) {
            ctx.MD_LOG("malloc() failed.");
            goto abort;
        }

        raw_off = 0;
        off = 0;

        while(raw_off < raw_size) {
            if(raw_text[raw_off] == '\0') {
                ret = (md_build_attr_append_substr(ctx, build, MD_TEXT_NULLCHAR, off));
                if (ret < 0) goto abort;
                memcpy(build.text + off, raw_text + raw_off, 1);
                off++;
                raw_off++;
                continue;
            }

            if(raw_text[raw_off] == '&') {
                OFF ent_end;

                if(md_is_entity_str(ctx, raw_text, raw_off, raw_size, &ent_end)) {
                    ret = (md_build_attr_append_substr(ctx, build, MD_TEXT_ENTITY, off));
                    if (ret < 0) goto abort;
                    memcpy(build.text + off, raw_text + raw_off, ent_end - raw_off);
                    off += ent_end - raw_off;
                    raw_off = ent_end;
                    continue;
                }
            }

            if(build.substr_count == 0  ||  build.substr_types[build.substr_count-1] != MD_TEXT_NORMAL)
            {
                ret = (md_build_attr_append_substr(ctx, build, MD_TEXT_NORMAL, off));
                if (ret < 0) goto abort;
            }

            if(!(flags & MD_BUILD_ATTR_NO_ESCAPES)  &&
               raw_text[raw_off] == '\\'  &&  raw_off+1 < raw_size  &&
               (ISPUNCT_(raw_text[raw_off+1]) || ISNEWLINE_(raw_text[raw_off+1])))
                raw_off++;

            build.text[off++] = raw_text[raw_off++];
        }
        build.substr_offsets[build.substr_count] = off;
    }

    attr.text = build.text;
    attr.size = off;
    attr.substr_offsets = build.substr_offsets;
    attr.substr_types = build.substr_types;
    return 0;

abort:
    md_free_attribute(ctx, build);
    return -1;
}


/*********************************************
 ***  Dictionary of Reference Definitions  ***
 *********************************************/

enum MD_FNV1A_BASE =  2166136261;
enum MD_FNV1A_PRIME = 16777619;

uint md_fnv1a(uint base, const(void)* data, size_t n)
{
    const(ubyte)* buf = cast(const(ubyte)*) data;
    uint hash = base;
    size_t i;

    for(i = 0; i < n; i++) {
        hash ^= buf[i];
        hash *= MD_FNV1A_PRIME;
    }

    return hash;
}


struct MD_REF_DEF
{
    const(CHAR)* label;
    const(CHAR)* title;
    uint hash;
    SZ label_size;
    bool label_needs_free;
    bool title_needs_free;
    SZ title_size;
    OFF dest_beg;
    OFF dest_end;
};

/* Label equivalence is quite complicated with regards to whitespace and case
 * folding. This complicates computing a hash of it as well as direct comparison
 * of two labels. */

uint md_link_label_hash(const(CHAR)* label, SZ size)
{
    uint hash = MD_FNV1A_BASE;
    OFF off;
    uint codepoint;
    int is_whitespace = FALSE;

    off = md_skip_unicode_whitespace(label, 0, size);
    while(off < size) {
        SZ char_size;

        codepoint = md_decode_unicode(label, off, size, &char_size);
        is_whitespace = ISUNICODEWHITESPACE_(codepoint) || ISNEWLINE_(label[off]);

        if(is_whitespace) {
            codepoint = ' ';
            hash = md_fnv1a(hash, &codepoint, uint.sizeof);
            off = md_skip_unicode_whitespace(label, off, size);
        } else {
            MD_UNICODE_FOLD_INFO fold_info;

            md_get_unicode_fold_info(codepoint, &fold_info);
            hash = md_fnv1a(hash, fold_info.codepoints.ptr, fold_info.n_codepoints * uint.sizeof);
            off += char_size;
        }
    }

    return hash;
}

OFF md_link_label_cmp_load_fold_info(const(CHAR)* label, OFF off, SZ size,
                                     MD_UNICODE_FOLD_INFO* fold_info)
{
    uint codepoint;
    SZ char_size;

    if(off >= size) {
        /* Treat end of link label as a whitespace. */
        goto whitespace;
    }

    if(ISNEWLINE_(label[off])) {
        /* Treat new lines as a whitespace. */
        off++;
        goto whitespace;
    }

    codepoint = md_decode_unicode(label, off, size, &char_size);
    off += char_size;
    if(ISUNICODEWHITESPACE_(codepoint)) {
        /* Treat all whitespace as equivalent */
        goto whitespace;
    }

    /* Get real folding info. */
    md_get_unicode_fold_info(codepoint, fold_info);
    return off;

whitespace:
    fold_info.codepoints[0] = ' ';
    fold_info.n_codepoints = 1;
    return off;
}

static int
md_link_label_cmp(const(CHAR)* a_label, SZ a_size, const(CHAR)* b_label, SZ b_size)
{
    OFF a_off;
    OFF b_off;
    int a_reached_end = FALSE;
    int b_reached_end = FALSE;
    MD_UNICODE_FOLD_INFO a_fi = { 0 };
    MD_UNICODE_FOLD_INFO b_fi = { 0 };
    OFF a_fi_off = 0;
    OFF b_fi_off = 0;
    int cmp;

    a_off = md_skip_unicode_whitespace(a_label, 0, a_size);
    b_off = md_skip_unicode_whitespace(b_label, 0, b_size);
    while(!a_reached_end  &&  !b_reached_end) {
        /* If needed, load fold info for next char. */
        if(a_fi_off >= a_fi.n_codepoints) {
            a_fi_off = 0;
            a_off = md_link_label_cmp_load_fold_info(a_label, a_off, a_size, &a_fi);
            a_reached_end = (a_off >= a_size);
        }
        if(b_fi_off >= b_fi.n_codepoints) {
            b_fi_off = 0;
            b_off = md_link_label_cmp_load_fold_info(b_label, b_off, b_size, &b_fi);
            b_reached_end = (b_off >= b_size);
        }

        cmp = b_fi.codepoints[b_fi_off] - a_fi.codepoints[a_fi_off];
        if(cmp != 0)
            return cmp;

        a_fi_off++;
        b_fi_off++;
    }

    return 0;
}

struct MD_REF_DEF_LIST
{
nothrow:
@nogc:

    int n_ref_defs;
    int alloc_ref_defs;

    /* Valid items always point into ctx.ref_defs[] */
    MD_REF_DEF* ref_defs_space; // Starting here, a list of pointer at the end of the struct

    // To allocate a MD_REF_DEF_LIST
    static size_t SIZEOF(int numDefRefs)
    {
        return 8 + (MD_REF_DEF*).sizeof * numDefRefs;
    }

    // Returns: a slice of ref defs embedded at the end of the struct
    static MD_REF_DEF*[] refDefs(MD_REF_DEF_LIST* list)
    {
        return (&(list.ref_defs_space))[0..list.n_ref_defs];
    }

    ref MD_REF_DEF* ref_defs_nth(size_t index)
    {
        MD_REF_DEF** base = &ref_defs_space;
        return base[index];
    }
}

extern(C) int md_ref_def_cmp(scope const(void)* a, scope const void* b)
{
    const(MD_REF_DEF)* a_ref = *cast(const(MD_REF_DEF*)*)a;
    const(MD_REF_DEF)* b_ref = *cast(const(MD_REF_DEF*)*)b;

    if(a_ref.hash < b_ref.hash)
        return -1;
    else if(a_ref.hash > b_ref.hash)
        return +1;
    else
        return md_link_label_cmp(a_ref.label, a_ref.label_size, b_ref.label, b_ref.label_size);
}

extern(C) int md_ref_def_cmp_stable(scope const(void)* a, scope const(void)* b)
{
    int cmp;

    cmp = md_ref_def_cmp(a, b);

    /* Ensure stability of the sorting. */
    if(cmp == 0) {
        const(MD_REF_DEF)* a_ref = *cast(const(MD_REF_DEF*)*)a;
        const(MD_REF_DEF)* b_ref = *cast(const(MD_REF_DEF*)*)b;

        if(a_ref < b_ref)
            cmp = -1;
        else if(a_ref > b_ref)
            cmp = +1;
        else
            cmp = 0;
    }

    return cmp;
}

int md_build_ref_def_hashtable(MD_CTX* ctx)
{
    int i, j;

    if(ctx.n_ref_defs == 0)
        return 0;

    ctx.ref_def_hashtable_size = (ctx.n_ref_defs * 5) / 4;
    ctx.ref_def_hashtable = cast(void**) malloc(ctx.ref_def_hashtable_size * (void*).sizeof);
    if(ctx.ref_def_hashtable == null) {
        ctx.MD_LOG("malloc() failed.");
        goto abort;
    }
    memset(ctx.ref_def_hashtable, 0, ctx.ref_def_hashtable_size * (void*).sizeof);

    /* Each member of ctx.ref_def_hashtable[] can be:
     *  -- null,
     *  -- pointer to the MD_REF_DEF in ctx.ref_defs[], or
     *  -- pointer to a MD_REF_DEF_LIST, which holds multiple pointers to
     *     such MD_REF_DEFs.
     */
    for(i = 0; i < ctx.n_ref_defs; i++) {
        MD_REF_DEF* def = &ctx.ref_defs[i];
        void* bucket;
        MD_REF_DEF_LIST* list;

        def.hash = md_link_label_hash(def.label, def.label_size);
        bucket = ctx.ref_def_hashtable[def.hash % ctx.ref_def_hashtable_size];

        if(bucket == null) {
            ctx.ref_def_hashtable[def.hash % ctx.ref_def_hashtable_size] = def;
            continue;
        }

        if(ctx.ref_defs <= cast(MD_REF_DEF*) bucket  &&  cast(MD_REF_DEF*) bucket < ctx.ref_defs + ctx.n_ref_defs) {
            /* The bucket already contains one ref. def. Lets see whether it
             * is the same label (ref. def. duplicate) or different one
             * (hash conflict). */
            MD_REF_DEF* old_def = cast(MD_REF_DEF*) bucket;

            if(md_link_label_cmp(def.label, def.label_size, old_def.label, old_def.label_size) == 0) {
                /* Ignore this ref. def. */
                continue;
            }

            /* Make the bucket capable of holding more ref. defs. */
            list = cast(MD_REF_DEF_LIST*) malloc(MD_REF_DEF_LIST.SIZEOF(4));
            if(list == null) {
                ctx.MD_LOG("malloc() failed.");
                goto abort;
            }
            list.ref_defs_nth(0) = old_def;
            list.ref_defs_nth(1) = def;
            list.n_ref_defs = 2;
            list.alloc_ref_defs = 4;
            ctx.ref_def_hashtable[def.hash % ctx.ref_def_hashtable_size] = list;
            continue;
        }

        /* Append the def to the bucket list. */
        list = cast(MD_REF_DEF_LIST*) bucket;
        if(list.n_ref_defs >= list.alloc_ref_defs) {
            MD_REF_DEF_LIST* list_tmp = cast(MD_REF_DEF_LIST*) realloc_safe(list, MD_REF_DEF_LIST.SIZEOF( 2 * list.alloc_ref_defs ));
            if(list_tmp == null) {
                ctx.MD_LOG("realloc() failed.");
                goto abort;
            }
            list = list_tmp;
            list.alloc_ref_defs *= 2;
            ctx.ref_def_hashtable[def.hash % ctx.ref_def_hashtable_size] = list;
        }

        list.ref_defs_nth(list.n_ref_defs) = def;
        list.n_ref_defs++;
    }

    /* Sort the complex buckets so we can use bsearch() with them. */
    for(i = 0; i < ctx.ref_def_hashtable_size; i++) {
        void* bucket = ctx.ref_def_hashtable[i];
        MD_REF_DEF_LIST* list;

        if(bucket == null)
            continue;
        if(ctx.ref_defs <= cast(MD_REF_DEF*) bucket  && cast(MD_REF_DEF*) bucket < ctx.ref_defs + ctx.n_ref_defs)
            continue;

        list = cast(MD_REF_DEF_LIST*) bucket;
        qsort(MD_REF_DEF_LIST.refDefs(list).ptr, list.n_ref_defs, (MD_REF_DEF*).sizeof, &md_ref_def_cmp_stable);

        /* Disable duplicates. */
        for(j = 1; j < list.n_ref_defs; j++) {
            if(md_ref_def_cmp(&list.ref_defs_nth(j-1), &list.ref_defs_nth(j)) == 0)
                list.ref_defs_nth(j) = list.ref_defs_nth(j-1);
        }
    }

    return 0;

abort:
    return -1;
}

static void
md_free_ref_def_hashtable(MD_CTX* ctx)
{
    if(ctx.ref_def_hashtable != null) {
        int i;

        for(i = 0; i < ctx.ref_def_hashtable_size; i++) {
            void* bucket = ctx.ref_def_hashtable[i];
            if(bucket == null)
                continue;
            if(ctx.ref_defs <= cast(MD_REF_DEF*) bucket  && cast(MD_REF_DEF*) bucket < ctx.ref_defs + ctx.n_ref_defs)
                continue;
            free(bucket);
        }

        free(ctx.ref_def_hashtable);
    }
}

const(MD_REF_DEF)* md_lookup_ref_def(MD_CTX* ctx, const(CHAR)* label, SZ label_size)
{
    uint hash;
    void* bucket;

    if(ctx.ref_def_hashtable_size == 0)
        return null;

    hash = md_link_label_hash(label, label_size);
    bucket = ctx.ref_def_hashtable[hash % ctx.ref_def_hashtable_size];

    if(bucket == null) {
        return null;
    } else if(ctx.ref_defs <= cast(MD_REF_DEF*) bucket  &&  cast(MD_REF_DEF*) bucket < ctx.ref_defs + ctx.n_ref_defs) {
        const MD_REF_DEF* def = cast(MD_REF_DEF*) bucket;

        if(md_link_label_cmp(def.label, def.label_size, label, label_size) == 0)
            return def;
        else
            return null;
    } else {
        MD_REF_DEF_LIST* list = cast(MD_REF_DEF_LIST*) bucket;
        MD_REF_DEF key_buf;
        const MD_REF_DEF* key = &key_buf;
        const(MD_REF_DEF*)* ret;

        key_buf.label = cast(CHAR*) label;
        key_buf.label_size = label_size;
        key_buf.hash = md_link_label_hash(key_buf.label, key_buf.label_size);

        ret = cast(const(MD_REF_DEF*)*) bsearch(&key, MD_REF_DEF_LIST.refDefs(list).ptr,
                    list.n_ref_defs, (MD_REF_DEF*).sizeof, &md_ref_def_cmp);
        if(ret != null)
            return *ret;
        else
            return null;
    }
}


/***************************
 ***  Recognizing Links  ***
 ***************************/

/* Note this code is partially shared between processing inlines and blocks
 * as reference definitions and links share some helper parser functions.
 */

struct MD_LINK_ATTR
{
    OFF dest_beg;
    OFF dest_end;

    const(CHAR)* title;
    SZ title_size;
    bool title_needs_free;
}


static int
md_is_link_label(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg,
                 OFF* p_end, int* p_beg_line_index, int* p_end_line_index,
                 OFF* p_contents_beg, OFF* p_contents_end)
{
    OFF off = beg;
    OFF contents_beg = 0;
    OFF contents_end = 0;
    int line_index = 0;
    int len = 0;

    if(ctx.CH(off) != '[')
        return FALSE;
    off++;

    while(1) {
        OFF line_end = lines[line_index].end;

        while(off < line_end) {
            if(ctx.CH(off) == '\\'  &&  off+1 < ctx.size  &&  (ctx.ISPUNCT(off+1) || ctx.ISNEWLINE(off+1))) {
                if(contents_end == 0) {
                    contents_beg = off;
                    *p_beg_line_index = line_index;
                }
                contents_end = off + 2;
                off += 2;
            } else if(ctx.CH(off) == '[') {
                return FALSE;
            } else if(ctx.CH(off) == ']') {
                if(contents_beg < contents_end) {
                    /* Success. */
                    *p_contents_beg = contents_beg;
                    *p_contents_end = contents_end;
                    *p_end = off+1;
                    *p_end_line_index = line_index;
                    return TRUE;
                } else {
                    /* Link label must have some non-whitespace contents. */
                    return FALSE;
                }
            } else {
                uint codepoint;
                SZ char_size;

                codepoint = md_decode_unicode(ctx.text, off, ctx.size, &char_size);
                if(!ISUNICODEWHITESPACE_(codepoint)) {
                    if(contents_end == 0) {
                        contents_beg = off;
                        *p_beg_line_index = line_index;
                    }
                    contents_end = off + char_size;
                }

                off += char_size;
            }

            len++;
            if(len > 999)
                return FALSE;
        }

        line_index++;
        len++;
        if(line_index < n_lines)
            off = lines[line_index].beg;
        else
            break;
    }

    return FALSE;
}

static int
md_is_link_destination_A(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end,
                         OFF* p_contents_beg, OFF* p_contents_end)
{
    OFF off = beg;

    if(off >= max_end  ||  ctx.CH(off) != '<')
        return FALSE;
    off++;

    while(off < max_end) {
        if(ctx.CH(off) == '\\'  &&  off+1 < max_end  &&  ctx.ISPUNCT(off+1)) {
            off += 2;
            continue;
        }

        if(ctx.ISNEWLINE(off)  ||  ctx.CH(off) == '<')
            return FALSE;

        if(ctx.CH(off) == '>') {
            /* Success. */
            *p_contents_beg = beg+1;
            *p_contents_end = off;
            *p_end = off+1;
            return TRUE;
        }

        off++;
    }

    return FALSE;
}

static int
md_is_link_destination_B(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end,
                         OFF* p_contents_beg, OFF* p_contents_end)
{
    OFF off = beg;
    int parenthesis_level = 0;

    while(off < max_end) {
        if(ctx.CH(off) == '\\'  &&  off+1 < max_end  &&  ctx.ISPUNCT(off+1)) {
            off += 2;
            continue;
        }

        if(ctx.ISWHITESPACE(off) || ctx.ISCNTRL(off))
            break;

        /* Link destination may include balanced pairs of unescaped '(' ')'.
         * Note we limit the maximal nesting level by 32 to protect us from
         * https://github.com/jgm/cmark/issues/214 */
        if(ctx.CH(off) == '(') {
            parenthesis_level++;
            if(parenthesis_level > 32)
                return FALSE;
        } else if(ctx.CH(off) == ')') {
            if(parenthesis_level == 0)
                break;
            parenthesis_level--;
        }

        off++;
    }

    if(parenthesis_level != 0  ||  off == beg)
        return FALSE;

    /* Success. */
    *p_contents_beg = beg;
    *p_contents_end = off;
    *p_end = off;
    return TRUE;
}

static int
md_is_link_destination(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end,
                       OFF* p_contents_beg, OFF* p_contents_end)
{
    if(ctx.CH(beg) == '<')
        return md_is_link_destination_A(ctx, beg, max_end, p_end, p_contents_beg, p_contents_end);
    else
        return md_is_link_destination_B(ctx, beg, max_end, p_end, p_contents_beg, p_contents_end);
}

static int
md_is_link_title(MD_CTX* ctx, const MD_LINE* lines, int n_lines, OFF beg,
                 OFF* p_end, int* p_beg_line_index, int* p_end_line_index,
                 OFF* p_contents_beg, OFF* p_contents_end)
{
    OFF off = beg;
    CHAR closer_char;
    int line_index = 0;

    /* White space with up to one line break. */
    while(off < lines[line_index].end  &&  ctx.ISWHITESPACE(off))
        off++;
    if(off >= lines[line_index].end) {
        line_index++;
        if(line_index >= n_lines)
            return FALSE;
        off = lines[line_index].beg;
    }
    if(off == beg)
        return FALSE;

    *p_beg_line_index = line_index;

    /* First char determines how to detect end of it. */
    switch(ctx.CH(off)) {
        case '"':   closer_char = '"'; break;
        case '\'':  closer_char = '\''; break;
        case '(':   closer_char = ')'; break;
        default:        return FALSE;
    }
    off++;

    *p_contents_beg = off;

    while(line_index < n_lines) {
        OFF line_end = lines[line_index].end;

        while(off < line_end) {
            if(ctx.CH(off) == '\\'  &&  off+1 < ctx.size  &&  (ctx.ISPUNCT(off+1) || ctx.ISNEWLINE(off+1))) {
                off++;
            } else if(ctx.CH(off) == closer_char) {
                /* Success. */
                *p_contents_end = off;
                *p_end = off+1;
                *p_end_line_index = line_index;
                return TRUE;
            } else if(closer_char == ')'  &&  ctx.CH(off) == '(') {
                /* ()-style title cannot contain (unescaped '(')) */
                return FALSE;
            }

            off++;
        }

        line_index++;
    }

    return FALSE;
}

/* Returns 0 if it is not a reference definition.
 *
 * Returns N > 0 if it is a reference definition. N then corresponds to the
 * number of lines forming it). In this case the definition is stored for
 * resolving any links referring to it.
 *
 * Returns -1 in case of an error (out of memory).
 */
int md_is_link_reference_definition(MD_CTX* ctx, const(MD_LINE)* lines, int n_lines)
{
    OFF label_contents_beg;
    OFF label_contents_end;
    int label_contents_line_index = -1;
    int label_is_multiline;
    const(CHAR)* label;
    SZ label_size;
    bool label_needs_free = false;
    OFF dest_contents_beg;
    OFF dest_contents_end;
    OFF title_contents_beg;
    OFF title_contents_end;
    int title_contents_line_index;
    int title_is_multiline;
    OFF off;
    int line_index = 0;
    int tmp_line_index;
    MD_REF_DEF* def;
    int ret;

    /* Link label. */
    if(!md_is_link_label(ctx, lines, n_lines, lines[0].beg,
                &off, &label_contents_line_index, &line_index,
                &label_contents_beg, &label_contents_end))
        return FALSE;
    label_is_multiline = (label_contents_line_index != line_index);

    /* Colon. */
    if(off >= lines[line_index].end  ||  ctx.CH(off) != ':')
        return FALSE;
    off++;

    /* Optional white space with up to one line break. */
    while(off < lines[line_index].end  &&  ctx.ISWHITESPACE(off))
        off++;
    if(off >= lines[line_index].end) {
        line_index++;
        if(line_index >= n_lines)
            return FALSE;
        off = lines[line_index].beg;
    }

    /* Link destination. */
    if(!md_is_link_destination(ctx, off, lines[line_index].end,
                &off, &dest_contents_beg, &dest_contents_end))
        return FALSE;

    /* (Optional) title. Note we interpret it as an title only if nothing
     * more follows on its last line. */
    if(md_is_link_title(ctx, lines + line_index, n_lines - line_index, off,
                &off, &title_contents_line_index, &tmp_line_index,
                &title_contents_beg, &title_contents_end)
        &&  off >= lines[line_index + tmp_line_index].end)
    {
        title_is_multiline = (tmp_line_index != title_contents_line_index);
        title_contents_line_index += line_index;
        line_index += tmp_line_index;
    } else {
        /* Not a title. */
        title_is_multiline = FALSE;
        title_contents_beg = off;
        title_contents_end = off;
        title_contents_line_index = 0;
    }

    /* Nothing more can follow on the last line. */
    if(off < lines[line_index].end)
        return FALSE;

    /* Construct label. */
    if(!label_is_multiline) {
        label = cast(CHAR*) ctx.STR(label_contents_beg);
        label_size = label_contents_end - label_contents_beg;
        label_needs_free = false;
    } else {
        ret = (md_merge_lines_alloc(ctx, label_contents_beg, label_contents_end,
                    lines + label_contents_line_index, n_lines - label_contents_line_index,
                    ' ', &label, &label_size));
        if (ret < 0) goto abort;
        label_needs_free = true;
    }

    /* Store the reference definition. */
    if(ctx.n_ref_defs >= ctx.alloc_ref_defs) {
        MD_REF_DEF* new_defs;

        ctx.alloc_ref_defs = (ctx.alloc_ref_defs > 0 ? ctx.alloc_ref_defs * 2 : 16);
        new_defs = cast(MD_REF_DEF*) realloc_safe(ctx.ref_defs, ctx.alloc_ref_defs * MD_REF_DEF.sizeof);
        if(new_defs == null) {
            ctx.MD_LOG("realloc() failed.");
            ret = -1;
            goto abort;
        }

        ctx.ref_defs = new_defs;
    }

    def = &ctx.ref_defs[ctx.n_ref_defs];
    memset(def, 0, MD_REF_DEF.sizeof);

    def.label = label;
    def.label_size = label_size;
    def.label_needs_free = label_needs_free;

    def.dest_beg = dest_contents_beg;
    def.dest_end = dest_contents_end;

    if(title_contents_beg >= title_contents_end) {
        def.title = null;
        def.title_size = 0;
    } else if(!title_is_multiline) {
        def.title = cast(CHAR*) ctx.STR(title_contents_beg);
        def.title_size = title_contents_end - title_contents_beg;
    } else {
        ret = (md_merge_lines_alloc(ctx, title_contents_beg, title_contents_end,
                    lines + title_contents_line_index, n_lines - title_contents_line_index,
                    '\n', &def.title, &def.title_size));
        if (ret < 0) goto abort;
        def.title_needs_free = true;
    }

    /* Success. */
    ctx.n_ref_defs++;
    return line_index + 1;

abort:
    /* Failure. */
    if(label_needs_free)
        free(cast(void*)label); // Note: const_cast here
    return -1;
}

static int
md_is_link_reference(MD_CTX* ctx, const(MD_LINE)* lines, int n_lines,
                     OFF beg, OFF end, MD_LINK_ATTR* attr)
{
    const(MD_REF_DEF)* def;
    const(MD_LINE)* beg_line;
    const(MD_LINE)* end_line;
    const(CHAR)* label;
    SZ label_size;
    int ret;

    assert(ctx.CH(beg) == '[' || ctx.CH(beg) == '!');
    assert(ctx.CH(end-1) == ']');

    beg += (ctx.CH(beg) == '!' ? 2 : 1);
    end--;

    /* Find lines corresponding to the beg and end positions. */
    assert(lines[0].beg <= beg);
    beg_line = lines;
    while(beg >= beg_line.end)
        beg_line++;

    assert(end <= lines[n_lines-1].end);
    end_line = beg_line;
    while(end >= end_line.end)
        end_line++;

    if(beg_line != end_line) {
        ret = (md_merge_lines_alloc(ctx, beg, end, beg_line,
            cast(int)(n_lines - (beg_line - lines)), ' ', &label, &label_size));
        if (ret < 0) goto abort;
    } else {
        label = cast(CHAR*) ctx.STR(beg);
        label_size = end - beg;
    }

    def = md_lookup_ref_def(ctx, label, label_size);
    if(def != null) {
        attr.dest_beg = def.dest_beg;
        attr.dest_end = def.dest_end;
        attr.title = def.title;
        attr.title_size = def.title_size;
        attr.title_needs_free = false;
    }

    if(beg_line != end_line)
        free(cast(void*)label); // Note: const_cast here

    ret = (def != null);

abort:
    return ret;
}

static int
md_is_inline_link_spec(MD_CTX* ctx, const MD_LINE* lines, int n_lines,
                       OFF beg, OFF* p_end, MD_LINK_ATTR* attr)
{
    int line_index = 0;
    int tmp_line_index;
    OFF title_contents_beg;
    OFF title_contents_end;
    int title_contents_line_index;
    int title_is_multiline;
    OFF off = beg;
    int ret = FALSE;

    while(off >= lines[line_index].end)
        line_index++;

    assert(ctx.CH(off) == '(');
    off++;

    /* Optional white space with up to one line break. */
    while(off < lines[line_index].end  &&  ctx.ISWHITESPACE(off))
        off++;
    if(off >= lines[line_index].end  &&  ctx.ISNEWLINE(off)) {
        line_index++;
        if(line_index >= n_lines)
            return FALSE;
        off = lines[line_index].beg;
    }

    /* Link destination may be omitted, but only when not also having a title. */
    if(off < ctx.size  &&  ctx.CH(off) == ')') {
        attr.dest_beg = off;
        attr.dest_end = off;
        attr.title = null;
        attr.title_size = 0;
        attr.title_needs_free = false;
        off++;
        *p_end = off;
        return TRUE;
    }

    /* Link destination. */
    if(!md_is_link_destination(ctx, off, lines[line_index].end,
                        &off, &attr.dest_beg, &attr.dest_end))
        return FALSE;

    /* (Optional) title. */
    if(md_is_link_title(ctx, lines + line_index, n_lines - line_index, off,
                &off, &title_contents_line_index, &tmp_line_index,
                &title_contents_beg, &title_contents_end))
    {
        title_is_multiline = (tmp_line_index != title_contents_line_index);
        title_contents_line_index += line_index;
        line_index += tmp_line_index;
    } else {
        /* Not a title. */
        title_is_multiline = FALSE;
        title_contents_beg = off;
        title_contents_end = off;
        title_contents_line_index = 0;
    }

    /* Optional whitespace followed with final ')'. */
    while(off < lines[line_index].end  &&  ctx.ISWHITESPACE(off))
        off++;
    if(off >= lines[line_index].end  &&  ctx.ISNEWLINE(off)) {
        line_index++;
        if(line_index >= n_lines)
            return FALSE;
        off = lines[line_index].beg;
    }
    if(ctx.CH(off) != ')')
        goto abort;
    off++;

    if(title_contents_beg >= title_contents_end) {
        attr.title = null;
        attr.title_size = 0;
        attr.title_needs_free = false;
    } else if(!title_is_multiline) {
        attr.title = cast(CHAR*) ctx.STR(title_contents_beg); // Note: const_cast here!
        attr.title_size = title_contents_end - title_contents_beg;
        attr.title_needs_free = false;
    } else {
        ret = (md_merge_lines_alloc(ctx, title_contents_beg, title_contents_end,
                    lines + title_contents_line_index, n_lines - title_contents_line_index,
                    '\n', &attr.title, &attr.title_size));
        if (ret < 0) goto abort;
        attr.title_needs_free = true;
    }

    *p_end = off;
    ret = TRUE;

abort:
    return ret;
}

void md_free_ref_defs(MD_CTX* ctx)
{
    int i;

    for(i = 0; i < ctx.n_ref_defs; i++) {
        MD_REF_DEF* def = &ctx.ref_defs[i];

        if(def.label_needs_free)
            free(cast(void*)def.label); // Note: const_cast here
        if(def.title_needs_free)
            free(cast(void*)def.title); // Note: const_cast here
    }

    free(ctx.ref_defs);
}


/******************************************
 ***  Processing Inlines (a.k.a Spans)  ***
 ******************************************/

/* We process inlines in few phases:
 *
 * (1) We go through the block text and collect all significant characters
 *     which may start/end a span or some other significant position into
 *     ctx.marks[]. Core of this is what md_collect_marks() does.
 *
 *     We also do some very brief preliminary context-less analysis, whether
 *     it might be opener or closer (e.g. of an emphasis span).
 *
 *     This speeds the other steps as we do not need to re-iterate over all
 *     characters anymore.
 *
 * (2) We analyze each potential mark types, in order by their precedence.
 *
 *     In each md_analyze_XXX() function, we re-iterate list of the marks,
 *     skipping already resolved regions (in preceding precedences) and try to
 *     resolve them.
 *
 * (2.1) For trivial marks, which are single (e.g. HTML entity), we just mark
 *       them as resolved.
 *
 * (2.2) For range-type marks, we analyze whether the mark could be closer
 *       and, if yes, whether there is some preceding opener it could satisfy.
 *
 *       If not we check whether it could be really an opener and if yes, we
 *       remember it so subsequent closers may resolve it.
 *
 * (3) Finally, when all marks were analyzed, we render the block contents
 *     by calling MD_RENDERER::text() callback, interrupting by ::enter_span()
 *     or ::close_span() whenever we reach a resolved mark.
 */


/* The mark structure.
 *
 * '\\': Maybe escape sequence.
 * '\0': null char.
 *  '*': Maybe (strong) emphasis start/end.
 *  '_': Maybe (strong) emphasis start/end.
 *  '~': Maybe strikethrough start/end (needs MD_FLAG_STRIKETHROUGH).
 *  '`': Maybe code span start/end.
 *  '&': Maybe start of entity.
 *  ';': Maybe end of entity.
 *  '<': Maybe start of raw HTML or autolink.
 *  '>': Maybe end of raw HTML or autolink.
 *  '[': Maybe start of link label or link text.
 *  '!': Equivalent of '[' for image.
 *  ']': Maybe end of link label or link text.
 *  '@': Maybe permissive e-mail auto-link (needs MD_FLAG_PERMISSIVEEMAILAUTOLINKS).
 *  ':': Maybe permissive URL auto-link (needs MD_FLAG_PERMISSIVEURLAUTOLINKS).
 *  '.': Maybe permissive WWW auto-link (needs MD_FLAG_PERMISSIVEWWWAUTOLINKS).
 *  'D': Dummy mark, it reserves a space for splitting a previous mark
 *       (e.g. emphasis) or to make more space for storing some special data
 *       related to the preceding mark (e.g. link).
 *
 * Note that not all instances of these chars in the text imply creation of the
 * structure. Only those which have (or may have, after we see more context)
 * the special meaning.
 *
 * (Keep this struct as small as possible to fit as much of them into CPU
 * cache line.)
 */

struct MD_MARK {
    OFF beg;
    OFF end;

    /* For unresolved openers, 'prev' and 'next' form the chain of open openers
     * of given type 'ch'.
     *
     * During resolving, we disconnect from the chain and point to the
     * corresponding counterpart so opener points to its closer and vice versa.
     */
    int prev;
    int next;
    CHAR ch;
    ubyte flags;
};

/* Mark flags (these apply to ALL mark types). */
enum MD_MARK_POTENTIAL_OPENER            = 0x01;  /* Maybe opener. */
enum MD_MARK_POTENTIAL_CLOSER            = 0x02;  /* Maybe closer. */
enum MD_MARK_OPENER                      = 0x04;  /* Definitely opener. */
enum MD_MARK_CLOSER                      = 0x08;  /* Definitely closer. */
enum MD_MARK_RESOLVED                    = 0x10;  /* Resolved in any definite way. */

/* Mark flags specific for various mark types (so they can share bits). */
enum MD_MARK_EMPH_INTRAWORD              = 0x20;  /* Helper for the "rule of 3". */
enum MD_MARK_EMPH_MOD3_0                 = 0x40;
enum MD_MARK_EMPH_MOD3_1                 = 0x80;
enum MD_MARK_EMPH_MOD3_2                 = (0x40 | 0x80);
enum MD_MARK_EMPH_MOD3_MASK              = (0x40 | 0x80);
enum MD_MARK_AUTOLINK                    = 0x20;  /* Distinguisher for '<', '>'. */
enum MD_MARK_VALIDPERMISSIVEAUTOLINK     = 0x20;  /* For permissive autolinks. */

MD_MARKCHAIN* md_asterisk_chain(MD_CTX* ctx, uint flags)
{
    switch(flags & (MD_MARK_EMPH_INTRAWORD | MD_MARK_EMPH_MOD3_MASK))
    {
        case MD_MARK_EMPH_INTRAWORD | MD_MARK_EMPH_MOD3_0:  return ctx.ASTERISK_OPENERS_intraword_mod3_0;
        case MD_MARK_EMPH_INTRAWORD | MD_MARK_EMPH_MOD3_1:  return ctx.ASTERISK_OPENERS_intraword_mod3_1;
        case MD_MARK_EMPH_INTRAWORD | MD_MARK_EMPH_MOD3_2:  return ctx.ASTERISK_OPENERS_intraword_mod3_2;
        case MD_MARK_EMPH_MOD3_0:                           return ctx.ASTERISK_OPENERS_extraword_mod3_0;
        case MD_MARK_EMPH_MOD3_1:                           return ctx.ASTERISK_OPENERS_extraword_mod3_1;
        case MD_MARK_EMPH_MOD3_2:                           return ctx.ASTERISK_OPENERS_extraword_mod3_2;
        default:                                            assert(false);
    }
}

MD_MARKCHAIN* md_mark_chain(MD_CTX* ctx, int mark_index)
{
    MD_MARK* mark = &ctx.marks[mark_index];

    switch(mark.ch) {
        case '*':   return md_asterisk_chain(ctx, mark.flags);
        case '_':   return ctx.UNDERSCORE_OPENERS;
        case '~':   return ctx.TILDE_OPENERS;
        case '[':   return ctx.BRACKET_OPENERS;
        case '|':   return ctx.TABLECELLBOUNDARIES;
        default:        return null;
    }
}

MD_MARK* md_push_mark(MD_CTX* ctx)
{
    if(ctx.n_marks >= ctx.alloc_marks) {
        MD_MARK* new_marks;

        ctx.alloc_marks = (ctx.alloc_marks > 0 ? ctx.alloc_marks * 2 : 64);
        new_marks = cast(MD_MARK*) realloc_safe(ctx.marks, ctx.alloc_marks * MD_MARK.sizeof);
        if(new_marks == null) {
            ctx.MD_LOG("realloc() failed.");
            return null;
        }

        ctx.marks = new_marks;
    }

    return &ctx.marks[ctx.n_marks++];
}

int PUSH_MARK_(MD_CTX* ctx, MD_MARK** mark)
{
    *mark = md_push_mark(ctx);
    if(*mark == null)
    {
        return -1;
    }
    return 0;
}

int PUSH_MARK(MD_CTX* ctx, MD_MARK** mark, CHAR ch_, OFF beg_, OFF end_, int flags_)
{
    int ret = PUSH_MARK_(ctx, mark);
    if (ret != 0)
        return ret;

    (*mark).beg = (beg_);
    (*mark).end = (end_);
    (*mark).prev = -1;
    (*mark).next = -1;
    (*mark).ch = cast(char)(ch_);
    (*mark).flags = cast(ubyte)flags_;
    return 0;
}

static void
md_mark_chain_append(MD_CTX* ctx, MD_MARKCHAIN* chain, int mark_index)
{
    if(chain.tail >= 0)
        ctx.marks[chain.tail].next = mark_index;
    else
        chain.head = mark_index;

    ctx.marks[mark_index].prev = chain.tail;
    chain.tail = mark_index;
}

/* Sometimes, we need to store a pointer into the mark. It is quite rare
 * so we do not bother to make MD_MARK use union, and it can only happen
 * for dummy marks. */
void md_mark_store_ptr(MD_CTX* ctx, int mark_index, const(void)* ptr)
{
    MD_MARK* mark = &ctx.marks[mark_index];
    assert(mark.ch == 'D');

    /* Check only members beg and end are misused for this. */
    assert((void*).sizeof <= 2 * OFF.sizeof);
    memcpy(mark, &ptr, (void*).sizeof);
}

static void*
md_mark_get_ptr(MD_CTX* ctx, int mark_index)
{
    void* ptr;
    MD_MARK* mark = &ctx.marks[mark_index];
    assert(mark.ch == 'D');
    memcpy(&ptr, mark, (void*).sizeof);
    return ptr;
}

static void
md_resolve_range(MD_CTX* ctx, MD_MARKCHAIN* chain, int opener_index, int closer_index)
{
    MD_MARK* opener = &ctx.marks[opener_index];
    MD_MARK* closer = &ctx.marks[closer_index];

    /* Remove opener from the list of openers. */
    if(chain != null) {
        if(opener.prev >= 0)
            ctx.marks[opener.prev].next = opener.next;
        else
            chain.head = opener.next;

        if(opener.next >= 0)
            ctx.marks[opener.next].prev = opener.prev;
        else
            chain.tail = opener.prev;
    }

    /* Interconnect opener and closer and mark both as resolved. */
    opener.next = closer_index;
    opener.flags |= MD_MARK_OPENER | MD_MARK_RESOLVED;
    closer.prev = opener_index;
    closer.flags |= MD_MARK_CLOSER | MD_MARK_RESOLVED;
}


enum MD_ROLLBACK_ALL         = 0;
enum MD_ROLLBACK_CROSSING    = 1;

/* In the range ctx.marks[opener_index] ... [closer_index], undo some or all
 * resolvings accordingly to these rules:
 *
 * (1) All openers BEFORE the range corresponding to any closer inside the
 *     range are un-resolved and they are re-added to their respective chains
 *     of unresolved openers. This ensures we can reuse the opener for closers
 *     AFTER the range.
 *
 * (2) If 'how' is MD_ROLLBACK_ALL, then ALL resolved marks inside the range
 *     are discarded.
 *
 * (3) If 'how' is MD_ROLLBACK_CROSSING, only closers with openers handled
 *     in (1) are discarded. I.e. pairs of openers and closers which are both
 *     inside the range are retained as well as any unpaired marks.
 */
static void
md_rollback(MD_CTX* ctx, int opener_index, int closer_index, int how)
{
    int i;
    int mark_index;

    /* Cut all unresolved openers at the mark index. */
    for(i = OPENERS_CHAIN_FIRST; i < OPENERS_CHAIN_LAST+1; i++) {
        MD_MARKCHAIN* chain = &ctx.mark_chains[i];

        while(chain.tail >= opener_index)
            chain.tail = ctx.marks[chain.tail].prev;

        if(chain.tail >= 0)
            ctx.marks[chain.tail].next = -1;
        else
            chain.head = -1;
    }

    /* Go backwards so that un-resolved openers are re-added into their
     * respective chains, in the right order. */
    mark_index = closer_index - 1;
    while(mark_index > opener_index) {
        MD_MARK* mark = &ctx.marks[mark_index];
        int mark_flags = mark.flags;
        int discard_flag = (how == MD_ROLLBACK_ALL);

        if(mark.flags & MD_MARK_CLOSER) {
            int mark_opener_index = mark.prev;

            /* Undo opener BEFORE the range. */
            if(mark_opener_index < opener_index) {
                MD_MARK* mark_opener = &ctx.marks[mark_opener_index];
                MD_MARKCHAIN* chain;

                mark_opener.flags &= ~(MD_MARK_OPENER | MD_MARK_CLOSER | MD_MARK_RESOLVED);
                chain = md_mark_chain(ctx, opener_index);
                if(chain != null) {
                    md_mark_chain_append(ctx, chain, mark_opener_index);
                    discard_flag = 1;
                }
            }
        }

        /* And reset our flags. */
        if(discard_flag)
            mark.flags &= ~(MD_MARK_OPENER | MD_MARK_CLOSER | MD_MARK_RESOLVED);

        /* Jump as far as we can over unresolved or non-interesting marks. */
        switch(how) {
            case MD_ROLLBACK_CROSSING:
                if((mark_flags & MD_MARK_CLOSER)  &&  mark.prev > opener_index) {
                    /* If we are closer with opener INSIDE the range, there may
                     * not be any other crosser inside the subrange. */
                    mark_index = mark.prev;
                    break;
                }
                goto default;
                /* Pass through. */
            default:
                mark_index--;
                break;
        }
    }
}

void md_build_mark_char_map(MD_CTX* ctx)
{
    memset(ctx.mark_char_map.ptr, 0, ctx.mark_char_map.length);

    ctx.mark_char_map['\\'] = 1;
    ctx.mark_char_map['*'] = 1;
    ctx.mark_char_map['_'] = 1;
    ctx.mark_char_map['`'] = 1;
    ctx.mark_char_map['&'] = 1;
    ctx.mark_char_map[';'] = 1;
    ctx.mark_char_map['<'] = 1;
    ctx.mark_char_map['>'] = 1;
    ctx.mark_char_map['['] = 1;
    ctx.mark_char_map['!'] = 1;
    ctx.mark_char_map[']'] = 1;
    ctx.mark_char_map['\0'] = 1;

    if(ctx.parser.flags & MD_FLAG_STRIKETHROUGH)
        ctx.mark_char_map['~'] = 1;

    if(ctx.parser.flags & MD_FLAG_LATEXMATHSPANS)
        ctx.mark_char_map['$'] = 1;

    if(ctx.parser.flags & MD_FLAG_PERMISSIVEEMAILAUTOLINKS)
        ctx.mark_char_map['@'] = 1;

    if(ctx.parser.flags & MD_FLAG_PERMISSIVEURLAUTOLINKS)
        ctx.mark_char_map[':'] = 1;

    if(ctx.parser.flags & MD_FLAG_PERMISSIVEWWWAUTOLINKS)
        ctx.mark_char_map['.'] = 1;

    if(ctx.parser.flags & MD_FLAG_TABLES)
        ctx.mark_char_map['|'] = 1;

    if(ctx.parser.flags & MD_FLAG_COLLAPSEWHITESPACE) {
        int i;

        for(i = 0; i < cast(int) (ctx.mark_char_map).sizeof; i++) {
            if(ISWHITESPACE_(cast(CHAR)i))
                ctx.mark_char_map[i] = 1;
        }
    }
}

/* We limit code span marks to lower then 32 backticks. This solves the
 * pathologic case of too many openers, each of different length: Their
 * resolving would be then O(n^2). */
enum CODESPAN_MARK_MAXLEN    = 32;

int md_is_code_span(MD_CTX* ctx, const(MD_LINE)* lines, int n_lines, OFF beg,
                    OFF* p_opener_beg, OFF* p_opener_end,
                    OFF* p_closer_beg, OFF* p_closer_end,
                    OFF* last_potential_closers,
                    int* p_reached_paragraph_end)
{
    OFF opener_beg = beg;
    OFF opener_end;
    OFF closer_beg;
    OFF closer_end;
    SZ mark_len;
    OFF line_end;
    int has_space_after_opener = FALSE;
    int has_eol_after_opener = FALSE;
    int has_space_before_closer = FALSE;
    int has_eol_before_closer = FALSE;
    int has_only_space = TRUE;
    int line_index = 0;

    line_end = lines[0].end;
    opener_end = opener_beg;
    while(opener_end < line_end  &&  ctx.CH(opener_end) == '`')
        opener_end++;
    has_space_after_opener = (opener_end < line_end && ctx.CH(opener_end) == ' ');
    has_eol_after_opener = (opener_end == line_end);

    /* The caller needs to know end of the opening mark even if we fail. */
    *p_opener_end = opener_end;

    mark_len = opener_end - opener_beg;
    if(mark_len > CODESPAN_MARK_MAXLEN)
        return FALSE;

    /* Check whether we already know there is no closer of this length.
     * If so, re-scan does no sense. This fixes issue #59. */
    if(last_potential_closers[mark_len-1] >= lines[n_lines-1].end  ||
       (*p_reached_paragraph_end  &&  last_potential_closers[mark_len-1] < opener_end))
        return FALSE;

    closer_beg = opener_end;
    closer_end = opener_end;

    /* Find closer mark. */
    while(TRUE) {
        while(closer_beg < line_end  &&  ctx.CH(closer_beg) != '`') {
            if(ctx.CH(closer_beg) != ' ')
                has_only_space = FALSE;
            closer_beg++;
        }
        closer_end = closer_beg;
        while(closer_end < line_end  &&  ctx.CH(closer_end) == '`')
            closer_end++;

        if(closer_end - closer_beg == mark_len) {
            /* Success. */
            has_space_before_closer = (closer_beg > lines[line_index].beg && ctx.CH(closer_beg-1) == ' ');
            has_eol_before_closer = (closer_beg == lines[line_index].beg);
            break;
        }

        if(closer_end - closer_beg > 0) {
            /* We have found a back-tick which is not part of the closer. */
            has_only_space = FALSE;

            /* But if we eventually fail, remember it as a potential closer
             * of its own length for future attempts. This mitigates needs for
             * rescans. */
            if(closer_end - closer_beg < CODESPAN_MARK_MAXLEN) {
                if(closer_beg > last_potential_closers[closer_end - closer_beg - 1])
                    last_potential_closers[closer_end - closer_beg - 1] = closer_beg;
            }
        }

        if(closer_end >= line_end) {
            line_index++;
            if(line_index >= n_lines) {
                /* Reached end of the paragraph and still nothing. */
                *p_reached_paragraph_end = TRUE;
                return FALSE;
            }
            /* Try on the next line. */
            line_end = lines[line_index].end;
            closer_beg = lines[line_index].beg;
        } else {
            closer_beg = closer_end;
        }
    }

    /* If there is a space or a new line both after and before the opener
     * (and if the code span is not made of spaces only), consume one initial
     * and one trailing space as part of the marks. */
    if(!has_only_space  &&
       (has_space_after_opener || has_eol_after_opener)  &&
       (has_space_before_closer || has_eol_before_closer))
    {
        if(has_space_after_opener)
            opener_end++;
        else
            opener_end = lines[1].beg;

        if(has_space_before_closer)
            closer_beg--;
        else {
            closer_beg = lines[line_index-1].end;
            /* We need to eat the preceding "\r\n" but not any line trailing
             * spaces. */
            while(closer_beg < ctx.size  &&  ctx.ISBLANK(closer_beg))
                closer_beg++;
        }
    }

    *p_opener_beg = opener_beg;
    *p_opener_end = opener_end;
    *p_closer_beg = closer_beg;
    *p_closer_end = closer_end;
    return TRUE;
}

static int
md_is_autolink_uri(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg+1;

    assert(ctx.CH(beg) == '<');

    /* Check for scheme. */
    if(off >= max_end  ||  !ctx.ISASCII(off))
        return FALSE;
    off++;
    while(1) {
        if(off >= max_end)
            return FALSE;
        if(off - beg > 32)
            return FALSE;
        if(ctx.CH(off) == ':'  &&  off - beg >= 3)
            break;
        if(!ctx.ISALNUM(off) && ctx.CH(off) != '+' && ctx.CH(off) != '-' && ctx.CH(off) != '.')
            return FALSE;
        off++;
    }

    /* Check the path after the scheme. */
    while(off < max_end  &&  ctx.CH(off) != '>') {
        if(ctx.ISWHITESPACE(off) || ctx.ISCNTRL(off) || ctx.CH(off) == '<')
            return FALSE;
        off++;
    }

    if(off >= max_end)
        return FALSE;

    assert(ctx.CH(off) == '>');
    *p_end = off+1;
    return TRUE;
}

static int
md_is_autolink_email(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end)
{
    OFF off = beg + 1;
    int label_len;

    assert(ctx.CH(beg) == '<');

    /* The code should correspond to this regexp:
            /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+
            @[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
            (?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
     */

    /* Username (before '@'). */
    while(off < max_end  &&  (ctx.ISALNUM(off) || ctx.ISANYOF(off, ".!#$%&'*+/=?^_`{|}~-")))
        off++;
    if(off <= beg+1)
        return FALSE;

    /* '@' */
    if(off >= max_end  ||  ctx.CH(off) != '@')
        return FALSE;
    off++;

    /* Labels delimited with '.'; each label is sequence of 1 - 62 alnum
     * characters or '-', but '-' is not allowed as first or last char. */
    label_len = 0;
    while(off < max_end) {
        if(ctx.ISALNUM(off))
            label_len++;
        else if(ctx.CH(off) == '-'  &&  label_len > 0)
            label_len++;
        else if(ctx.CH(off) == '.'  &&  label_len > 0  &&  ctx.CH(off-1) != '-')
            label_len = 0;
        else
            break;

        if(label_len > 62)
            return FALSE;

        off++;
    }

    if(label_len <= 0  || off >= max_end  ||  ctx.CH(off) != '>' ||  ctx.CH(off-1) == '-')
        return FALSE;

    *p_end = off+1;
    return TRUE;
}

static int
md_is_autolink(MD_CTX* ctx, OFF beg, OFF max_end, OFF* p_end, int* p_missing_mailto)
{
    if(md_is_autolink_uri(ctx, beg, max_end, p_end)) {
        *p_missing_mailto = FALSE;
        return TRUE;
    }

    if(md_is_autolink_email(ctx, beg, max_end, p_end)) {
        *p_missing_mailto = TRUE;
        return TRUE;
    }

    return FALSE;
}

/* For 8-bit encodings, mark_char_map[] covers all 256 elements. */
bool IS_MARK_CHAR(MD_CTX* ctx, OFF off)
{
    return (ctx.mark_char_map[cast(ubyte) ctx.CH(off)]) != 0;
}

int md_collect_marks(MD_CTX* ctx, const(MD_LINE)* lines, int n_lines, int table_mode)
{
    int i;
    int ret = 0;
    MD_MARK* mark;
    OFF[CODESPAN_MARK_MAXLEN] codespan_last_potential_closers =
    [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ];

    int codespan_scanned_till_paragraph_end = FALSE;

    for(i = 0; i < n_lines; i++)
    {
        const(MD_LINE)* line = &lines[i];
        OFF off = line.beg;
        OFF line_end = line.end;

        while(true)
        {
            CHAR ch;

            /* Optimization: Use some loop unrolling. */
            while(off + 3 < line_end  &&  !IS_MARK_CHAR(ctx, off+0)  &&  !IS_MARK_CHAR(ctx, off+1)
                                      &&  !IS_MARK_CHAR(ctx, off+2)  &&  !IS_MARK_CHAR(ctx, off+3))
                off += 4;
            while(off < line_end  &&  !IS_MARK_CHAR(ctx, off+0))
                off++;

            if(off >= line_end)
                break;

            ch = ctx.CH(off);

            /* A backslash escape.
             * It can go beyond line.end as it may involve escaped new
             * line to form a hard break. */
            if(ch == '\\'  &&  off+1 < ctx.size  &&  (ctx.ISPUNCT(off+1) || ctx.ISNEWLINE(off+1))) {
                /* Hard-break cannot be on the last line of the block. */
                if(!ctx.ISNEWLINE(off+1)  ||  i+1 < n_lines)
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off, off+2, MD_MARK_RESOLVED);
                    if (ret != 0) goto abort;
                }
                off += 2;
                continue;
            }

            /* A potential (string) emphasis start/end. */
            if(ch == '*'  ||  ch == '_') {
                OFF tmp = off+1;
                int left_level;     /* What precedes: 0 = whitespace; 1 = punctuation; 2 = other char. */
                int right_level;    /* What follows: 0 = whitespace; 1 = punctuation; 2 = other char. */

                while(tmp < line_end  &&  ctx.CH(tmp) == ch)
                    tmp++;

                if(off == line.beg  ||  ctx.ISUNICODEWHITESPACEBEFORE(off))
                    left_level = 0;
                else if(ctx.ISUNICODEPUNCTBEFORE(off))
                    left_level = 1;
                else
                    left_level = 2;

                if(tmp == line_end  ||  ctx.ISUNICODEWHITESPACE(tmp))
                    right_level = 0;
                else if(ctx.ISUNICODEPUNCT(tmp))
                    right_level = 1;
                else
                    right_level = 2;

                /* Intra-word underscore doesn't have special meaning. */
                if(ch == '_'  &&  left_level == 2  &&  right_level == 2) {
                    left_level = 0;
                    right_level = 0;
                }

                if(left_level != 0  ||  right_level != 0) {
                    uint flags = 0;

                    if(left_level > 0  &&  left_level >= right_level)
                        flags |= MD_MARK_POTENTIAL_CLOSER;
                    if(right_level > 0  &&  right_level >= left_level)
                        flags |= MD_MARK_POTENTIAL_OPENER;
                    if(left_level == 2  &&  right_level == 2)
                        flags |= MD_MARK_EMPH_INTRAWORD;

                    /* For "the rule of three" we need to remember the original
                     * size of the mark (modulo three), before we potentially
                     * split the mark when being later resolved partially by some
                     * shorter closer. */
                    switch((tmp - off) % 3)
                    {
                        case 0: flags |= MD_MARK_EMPH_MOD3_0; break;
                        case 1: flags |= MD_MARK_EMPH_MOD3_1; break;
                        case 2: flags |= MD_MARK_EMPH_MOD3_2; break;
                        default: break;
                    }

                    ret = PUSH_MARK(ctx, &mark, ch, off, tmp, flags);
                    if (ret != 0) goto abort;

                    /* During resolving, multiple asterisks may have to be
                     * split into independent span start/ends. Consider e.g.
                     * "**foo* bar*". Therefore we push also some empty dummy
                     * marks to have enough space for that. */
                    off++;
                    while(off < tmp) {
                        ret = PUSH_MARK(ctx,  &mark, 'D', off, off, 0);
                        if (ret != 0) goto abort;
                        off++;
                    }
                    continue;
                }

                off = tmp;
                continue;
            }

            /* A potential code span start/end. */
            if(ch == '`') {
                OFF opener_beg, opener_end;
                OFF closer_beg, closer_end;
                int is_code_span;

                is_code_span = md_is_code_span(ctx, lines + i, n_lines - i, off,
                                    &opener_beg, &opener_end, &closer_beg, &closer_end,
                                    codespan_last_potential_closers.ptr,
                                    &codespan_scanned_till_paragraph_end);
                if(is_code_span) {
                    ret = PUSH_MARK(ctx, &mark, '`', opener_beg, opener_end, MD_MARK_OPENER | MD_MARK_RESOLVED);
                    if (ret != 0) goto abort;
                    ret = PUSH_MARK(ctx, &mark, '`', closer_beg, closer_end, MD_MARK_CLOSER | MD_MARK_RESOLVED);
                    if (ret != 0) goto abort;
                    ctx.marks[ctx.n_marks-2].next = ctx.n_marks-1;
                    ctx.marks[ctx.n_marks-1].prev = ctx.n_marks-2;

                    off = closer_end;

                    /* Advance the current line accordingly. */
                    while(off > line_end) {
                        i++;
                        line++;
                        line_end = line.end;
                    }
                    continue;
                }

                off = opener_end;
                continue;
            }

            /* A potential entity start. */
            if(ch == '&') {
                ret = PUSH_MARK(ctx,  &mark, ch, off, off+1, MD_MARK_POTENTIAL_OPENER);
                if (ret != 0) goto abort;
                off++;
                continue;
            }

            /* A potential entity end. */
            if(ch == ';') {
                /* We surely cannot be entity unless the previous mark is '&'. */
                if(ctx.n_marks > 0  &&  ctx.marks[ctx.n_marks-1].ch == '&')
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off, off+1, MD_MARK_POTENTIAL_CLOSER);
                    if (ret != 0) goto abort;
                }

                off++;
                continue;
            }

            /* A potential autolink or raw HTML start/end. */
            if(ch == '<') {
                int is_autolink;
                OFF autolink_end;
                int missing_mailto;

                if(!(ctx.parser.flags & MD_FLAG_NOHTMLSPANS)) {
                    int is_html;
                    OFF html_end;

                    /* Given the nature of the raw HTML, we have to recognize
                     * it here. Doing so later in md_analyze_lt_gt() could
                     * open can of worms of quadratic complexity. */
                    is_html = md_is_html_any(ctx, lines + i, n_lines - i, off,
                                    lines[n_lines-1].end, &html_end);
                    if(is_html) {
                        ret = PUSH_MARK(ctx, &mark, '<', off, off, MD_MARK_OPENER | MD_MARK_RESOLVED);
                        if (ret != 0) goto abort;
                        ret = PUSH_MARK(ctx, &mark, '>', html_end, html_end, MD_MARK_CLOSER | MD_MARK_RESOLVED);
                        if (ret != 0) goto abort;
                        ctx.marks[ctx.n_marks-2].next = ctx.n_marks-1;
                        ctx.marks[ctx.n_marks-1].prev = ctx.n_marks-2;
                        off = html_end;

                        /* Advance the current line accordingly. */
                        while(off > line_end) {
                            i++;
                            line++;
                            line_end = line.end;
                        }
                        continue;
                    }
                }

                is_autolink = md_is_autolink(ctx, off, lines[n_lines-1].end,
                                    &autolink_end, &missing_mailto);
                if(is_autolink) {
                    ret = PUSH_MARK(ctx, &mark, (missing_mailto ? '@' : '<'), off, off+1,
                                    MD_MARK_OPENER | MD_MARK_RESOLVED | MD_MARK_AUTOLINK);
                    if (ret != 0) goto abort;
                    ret = PUSH_MARK(ctx, &mark, '>', autolink_end-1, autolink_end,
                                    MD_MARK_CLOSER | MD_MARK_RESOLVED | MD_MARK_AUTOLINK);
                    if (ret != 0) goto abort;
                    ctx.marks[ctx.n_marks-2].next = ctx.n_marks-1;
                    ctx.marks[ctx.n_marks-1].prev = ctx.n_marks-2;
                    off = autolink_end;
                    continue;
                }

                off++;
                continue;
            }

            /* A potential link or its part. */
            if(ch == '['  ||  (ch == '!' && off+1 < line_end && ctx.CH(off+1) == '[')) {
                OFF tmp = (ch == '[' ? off+1 : off+2);
                ret = PUSH_MARK(ctx, &mark, ch, off, tmp, MD_MARK_POTENTIAL_OPENER);
                if (ret != 0) goto abort;
                off = tmp;
                /* Two dummies to make enough place for data we need if it is
                 * a link. */
                ret = PUSH_MARK(ctx, &mark, 'D', off, off, 0);
                if (ret != 0) goto abort;
                ret = PUSH_MARK(ctx, &mark, 'D', off, off, 0);
                if (ret != 0) goto abort;
                continue;
            }
            if(ch == ']') {
                ret = PUSH_MARK(ctx, &mark, ch, off, off+1, MD_MARK_POTENTIAL_CLOSER);
                if (ret != 0) goto abort;
                off++;
                continue;
            }

            /* A potential permissive e-mail autolink. */
            if(ch == '@') {
                if(line.beg + 1 <= off  &&  ctx.ISALNUM(off-1)  &&
                    off + 3 < line.end  &&  ctx.ISALNUM(off+1))
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off, off+1, MD_MARK_POTENTIAL_OPENER);
                    if (ret != 0) goto abort;
                    /* Push a dummy as a reserve for a closer. */
                    ret = PUSH_MARK(ctx, &mark, 'D', off, off, 0);
                    if (ret != 0) goto abort;
                }

                off++;
                continue;
            }

            /* A potential permissive URL autolink. */
            if(ch == ':')
            {
                static struct Scheme
                {
                    const(CHAR)* scheme;
                    SZ scheme_size;
                    const(CHAR)* suffix;
                    SZ suffix_size;
                }

                static immutable Scheme[] scheme_map =
                [
                    Scheme("http", 4,    "//", 2),
                    Scheme("https", 5,    "//", 2),
                    Scheme("ftp", 3,    "//", 2)
                ];

                int scheme_index;

                for(scheme_index = 0; scheme_index < cast(int) (scheme_map.length); scheme_index++) {
                    const(CHAR)* scheme = scheme_map[scheme_index].scheme;
                    const SZ scheme_size = scheme_map[scheme_index].scheme_size;
                    const(CHAR)* suffix = scheme_map[scheme_index].suffix;
                    const SZ suffix_size = scheme_map[scheme_index].suffix_size;

                    if(line.beg + scheme_size <= off  &&  md_ascii_eq(ctx.STR(off-scheme_size), scheme, scheme_size)  &&
                        (line.beg + scheme_size == off || ctx.ISWHITESPACE(off-scheme_size-1) || ctx.ISANYOF(off-scheme_size-1, "*_~(["))  &&
                        off + 1 + suffix_size < line.end  &&  md_ascii_eq(ctx.STR(off+1), suffix, suffix_size))
                    {
                        ret = PUSH_MARK(ctx, &mark, ch, off-scheme_size, off+1+suffix_size, MD_MARK_POTENTIAL_OPENER);
                        if (ret != 0) goto abort;
                        /* Push a dummy as a reserve for a closer. */
                        ret = PUSH_MARK(ctx, &mark, 'D', off, off, 0);
                        if (ret != 0) goto abort;
                        off += 1 + suffix_size;
                        continue;
                    }
                }

                off++;
                continue;
            }

            /* A potential permissive WWW autolink. */
            if(ch == '.') {
                if(line.beg + 3 <= off  &&  md_ascii_eq(ctx.STR(off-3), "www", 3)  &&
                    (line.beg + 3 == off || ctx.ISWHITESPACE(off-4) || ctx.ISANYOF(off-4, "*_~(["))  &&
                    off + 1 < line_end)
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off-3, off+1, MD_MARK_POTENTIAL_OPENER);
                    if (ret != 0) goto abort;
                    /* Push a dummy as a reserve for a closer. */
                    ret = PUSH_MARK(ctx, &mark, 'D', off, off, 0);
                    if (ret != 0) goto abort;
                    off++;
                    continue;
                }

                off++;
                continue;
            }

            /* A potential table cell boundary. */
            if(table_mode  &&  ch == '|') {
                ret = PUSH_MARK(ctx, &mark, ch, off, off+1, 0);
                if (ret != 0) goto abort;
                off++;
                continue;
            }

            /* A potential strikethrough start/end. */
            if(ch == '~') {
                OFF tmp = off+1;

                while(tmp < line_end  &&  ctx.CH(tmp) == '~')
                    tmp++;

                ret = PUSH_MARK(ctx, &mark, ch, off, tmp, MD_MARK_POTENTIAL_OPENER | MD_MARK_POTENTIAL_CLOSER);
                if (ret != 0) goto abort;
                off = tmp;
                continue;
            }

            /* A potential equation start/end */
            if(ch == '$') {
                /* We can have at most two consecutive $ signs,
                 * where two dollar signs signify a display equation. */
                OFF tmp = off+1;

                while(tmp < line_end && ctx.CH(tmp) == '$')
                    tmp++;

                if (tmp - off <= 2)
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off, tmp, MD_MARK_POTENTIAL_OPENER | MD_MARK_POTENTIAL_CLOSER);
                    if (ret != 0) goto abort;
                }
                off = tmp;
                continue;
            }

            /* Turn non-trivial whitespace into single space. */
            if(ISWHITESPACE_(ch)) {
                OFF tmp = off+1;

                while(tmp < line_end  &&  ctx.ISWHITESPACE(tmp))
                    tmp++;

                if(tmp - off > 1  ||  ch != ' ')
                {
                    ret = PUSH_MARK(ctx, &mark, ch, off, tmp, MD_MARK_RESOLVED);
                    if (ret != 0) goto abort;
                }

                off = tmp;
                continue;
            }

            /* null character. */
            if(ch == '\0') {
                ret = PUSH_MARK(ctx, &mark, ch, off, off+1, MD_MARK_RESOLVED);
                if (ret != 0) goto abort;
                off++;
                continue;
            }

            off++;
        }
    }

    /* Add a dummy mark at the end of the mark vector to simplify
     * process_inlines(). */
    ret = PUSH_MARK(ctx, &mark, 127, ctx.size, ctx.size, MD_MARK_RESOLVED);
    if (ret != 0) goto abort;

abort:
    return ret;
}

static void
md_analyze_bracket(MD_CTX* ctx, int mark_index)
{
    /* We cannot really resolve links here as for that we would need
     * more context. E.g. a following pair of brackets (reference link),
     * or enclosing pair of brackets (if the inner is the link, the outer
     * one cannot be.)
     *
     * Therefore we here only construct a list of resolved '[' ']' pairs
     * ordered by position of the closer. This allows ur to analyze what is
     * or is not link in the right order, from inside to outside in case
     * of nested brackets.
     *
     * The resolving itself is deferred into md_resolve_links().
     */

    MD_MARK* mark = &ctx.marks[mark_index];

    if(mark.flags & MD_MARK_POTENTIAL_OPENER) {
        md_mark_chain_append(ctx, ctx.BRACKET_OPENERS, mark_index);
        return;
    }

    if(ctx.BRACKET_OPENERS.tail >= 0) {
        /* Pop the opener from the chain. */
        int opener_index = ctx.BRACKET_OPENERS.tail;
        MD_MARK* opener = &ctx.marks[opener_index];
        if(opener.prev >= 0)
            ctx.marks[opener.prev].next = -1;
        else
            ctx.BRACKET_OPENERS.head = -1;
        ctx.BRACKET_OPENERS.tail = opener.prev;

        /* Interconnect the opener and closer. */
        opener.next = mark_index;
        mark.prev = opener_index;

        /* Add the pair into chain of potential links for md_resolve_links().
         * Note we misuse opener.prev for this as opener.next points to its
         * closer. */
        if(ctx.unresolved_link_tail >= 0)
            ctx.marks[ctx.unresolved_link_tail].prev = opener_index;
        else
            ctx.unresolved_link_head = opener_index;
        ctx.unresolved_link_tail = opener_index;
        opener.prev = -1;
    }
}

/* Forward declaration. */
static void md_analyze_link_contents(MD_CTX* ctx, const MD_LINE* lines, int n_lines,
                                     int mark_beg, int mark_end);

static int
md_resolve_links(MD_CTX* ctx, const MD_LINE* lines, int n_lines)
{
    int opener_index = ctx.unresolved_link_head;
    OFF last_link_beg = 0;
    OFF last_link_end = 0;
    OFF last_img_beg = 0;
    OFF last_img_end = 0;

    while(opener_index >= 0) {
        MD_MARK* opener = &ctx.marks[opener_index];
        int closer_index = opener.next;
        MD_MARK* closer = &ctx.marks[closer_index];
        int next_index = opener.prev;
        MD_MARK* next_opener;
        MD_MARK* next_closer;
        MD_LINK_ATTR attr;
        int is_link = FALSE;

        if(next_index >= 0) {
            next_opener = &ctx.marks[next_index];
            next_closer = &ctx.marks[next_opener.next];
        } else {
            next_opener = null;
            next_closer = null;
        }

        /* If nested ("[ [ ] ]"), we need to make sure that:
         *   - The outer does not end inside of (...) belonging to the inner.
         *   - The outer cannot be link if the inner is link (i.e. not image).
         *
         * (Note we here analyze from inner to outer as the marks are ordered
         * by closer.beg.)
         */
        if((opener.beg < last_link_beg  &&  closer.end < last_link_end)  ||
           (opener.beg < last_img_beg  &&  closer.end < last_img_end)  ||
           (opener.beg < last_link_end  &&  opener.ch == '['))
        {
            opener_index = next_index;
            continue;
        }

        if(next_opener != null  &&  next_opener.beg == closer.end) {
            if(next_closer.beg > closer.end + 1) {
                /* Might be full reference link. */
                is_link = md_is_link_reference(ctx, lines, n_lines, next_opener.beg, next_closer.end, &attr);
            } else {
                /* Might be shortcut reference link. */
                is_link = md_is_link_reference(ctx, lines, n_lines, opener.beg, closer.end, &attr);
            }

            if(is_link < 0)
                return -1;

            if(is_link) {
                /* Eat the 2nd "[...]". */
                closer.end = next_closer.end;
            }
        } else {
            if(closer.end < ctx.size  &&  ctx.CH(closer.end) == '(') {
                /* Might be inline link. */
                OFF inline_link_end = uint.max;

                is_link = md_is_inline_link_spec(ctx, lines, n_lines, closer.end, &inline_link_end, &attr);
                if(is_link < 0)
                    return -1;

                /* Check the closing ')' is not inside an already resolved range
                 * (i.e. a range with a higher priority), e.g. a code span. */
                if(is_link) {
                    int i = closer_index + 1;

                    while(i < ctx.n_marks) {
                        MD_MARK* mark = &ctx.marks[i];

                        if(mark.beg >= inline_link_end)
                            break;
                        if((mark.flags & (MD_MARK_OPENER | MD_MARK_RESOLVED)) == (MD_MARK_OPENER | MD_MARK_RESOLVED)) {
                            if(ctx.marks[mark.next].beg >= inline_link_end) {
                                /* Cancel the link status. */
                                if(attr.title_needs_free)
                                    free(cast(void*)(attr.title));
                                is_link = FALSE;
                                break;
                            }

                            i = mark.next + 1;
                        } else {
                            i++;
                        }
                    }
                }

                if(is_link) {
                    /* Eat the "(...)" */
                    closer.end = inline_link_end;
                }
            }

            if(!is_link) {
                /* Might be collapsed reference link. */
                is_link = md_is_link_reference(ctx, lines, n_lines, opener.beg, closer.end, &attr);
                if(is_link < 0)
                    return -1;
            }
        }

        if(is_link) {
            /* Resolve the brackets as a link. */
            opener.flags |= MD_MARK_OPENER | MD_MARK_RESOLVED;
            closer.flags |= MD_MARK_CLOSER | MD_MARK_RESOLVED;

            /* If it is a link, we store the destination and title in the two
             * dummy marks after the opener. */
            assert(ctx.marks[opener_index+1].ch == 'D');
            ctx.marks[opener_index+1].beg = attr.dest_beg;
            ctx.marks[opener_index+1].end = attr.dest_end;

            assert(ctx.marks[opener_index+2].ch == 'D');
            md_mark_store_ptr(ctx, opener_index+2, attr.title);
            if(attr.title_needs_free)
                md_mark_chain_append(ctx, ctx.PTR_CHAIN, opener_index+2);
            ctx.marks[opener_index+2].prev = attr.title_size;

            if(opener.ch == '[') {
                last_link_beg = opener.beg;
                last_link_end = closer.end;
            } else {
                last_img_beg = opener.beg;
                last_img_end = closer.end;
            }

            md_analyze_link_contents(ctx, lines, n_lines, opener_index+1, closer_index);
        }

        opener_index = next_index;
    }

    return 0;
}

/* Analyze whether the mark '&' starts a HTML entity.
 * If so, update its flags as well as flags of corresponding closer ';'. */
static void
md_analyze_entity(MD_CTX* ctx, int mark_index)
{
    MD_MARK* opener = &ctx.marks[mark_index];
    MD_MARK* closer;
    OFF off;

    /* Cannot be entity if there is no closer as the next mark.
     * (Any other mark between would mean strange character which cannot be
     * part of the entity.
     *
     * So we can do all the work on '&' and do not call this later for the
     * closing mark ';'.
     */
    if(mark_index + 1 >= ctx.n_marks)
        return;
    closer = &ctx.marks[mark_index+1];
    if(closer.ch != ';')
        return;

    if(md_is_entity(ctx, opener.beg, closer.end, &off)) {
        assert(off == closer.end);

        md_resolve_range(ctx, null, mark_index, mark_index+1);
        opener.end = closer.end;
    }
}

static void
md_analyze_table_cell_boundary(MD_CTX* ctx, int mark_index)
{
    MD_MARK* mark = &ctx.marks[mark_index];
    mark.flags |= MD_MARK_RESOLVED;

    md_mark_chain_append(ctx, ctx.TABLECELLBOUNDARIES, mark_index);
    ctx.n_table_cell_boundaries++;
}

/* Split a longer mark into two. The new mark takes the given count of
 * characters. May only be called if an adequate number of dummy 'D' marks
 * follows.
 */
static int
md_split_emph_mark(MD_CTX* ctx, int mark_index, SZ n)
{
    MD_MARK* mark = &ctx.marks[mark_index];
    int new_mark_index = mark_index + (mark.end - mark.beg - n);
    MD_MARK* dummy = &ctx.marks[new_mark_index];

    assert(mark.end - mark.beg > n);
    assert(dummy.ch == 'D');

    memcpy(dummy, mark, MD_MARK.sizeof);
    mark.end -= n;
    dummy.beg = mark.end;

    return new_mark_index;
}

static void
md_analyze_emph(MD_CTX* ctx, int mark_index)
{
    MD_MARK* mark = &ctx.marks[mark_index];
    MD_MARKCHAIN* chain = md_mark_chain(ctx, mark_index);

    /* If we can be a closer, try to resolve with the preceding opener. */
    if(mark.flags & MD_MARK_POTENTIAL_CLOSER) {
        MD_MARK* opener = null;
        int opener_index;

        if(mark.ch == '*') {
            MD_MARKCHAIN*[6] opener_chains;
            int i, n_opener_chains;
            uint flags = mark.flags;

            /* Apply "rule of three". (This is why we break asterisk opener
             * marks into multiple chains.) */
            n_opener_chains = 0;
            opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_intraword_mod3_0;
            if((flags & MD_MARK_EMPH_MOD3_MASK) != MD_MARK_EMPH_MOD3_2)
                opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_intraword_mod3_1;
            if((flags & MD_MARK_EMPH_MOD3_MASK) != MD_MARK_EMPH_MOD3_1)
                opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_intraword_mod3_2;
            opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_extraword_mod3_0;
            if(!(flags & MD_MARK_EMPH_INTRAWORD)  ||  (flags & MD_MARK_EMPH_MOD3_MASK) != MD_MARK_EMPH_MOD3_2)
                opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_extraword_mod3_1;
            if(!(flags & MD_MARK_EMPH_INTRAWORD)  ||  (flags & MD_MARK_EMPH_MOD3_MASK) != MD_MARK_EMPH_MOD3_1)
                opener_chains[n_opener_chains++] = ctx.ASTERISK_OPENERS_extraword_mod3_2;

            /* Opener is the most recent mark from the allowed chains. */
            for(i = 0; i < n_opener_chains; i++) {
                if(opener_chains[i].tail >= 0) {
                    int tmp_index = opener_chains[i].tail;
                    MD_MARK* tmp_mark = &ctx.marks[tmp_index];
                    if(opener == null  ||  tmp_mark.end > opener.end) {
                        opener_index = tmp_index;
                        opener = tmp_mark;
                    }
                }
            }
        } else {
            /* Simple emph. mark */
            if(chain.tail >= 0) {
                opener_index = chain.tail;
                opener = &ctx.marks[opener_index];
            }
        }

        /* Resolve, if we have found matching opener. */
        if(opener != null) {
            SZ opener_size = opener.end - opener.beg;
            SZ closer_size = mark.end - mark.beg;

            if(opener_size > closer_size) {
                opener_index = md_split_emph_mark(ctx, opener_index, closer_size);
                md_mark_chain_append(ctx, md_mark_chain(ctx, opener_index), opener_index);
            } else if(opener_size < closer_size) {
                md_split_emph_mark(ctx, mark_index, closer_size - opener_size);
            }

            md_rollback(ctx, opener_index, mark_index, MD_ROLLBACK_CROSSING);
            md_resolve_range(ctx, chain, opener_index, mark_index);
            return;
        }
    }

    /* If we could not resolve as closer, we may be yet be an opener. */
    if(mark.flags & MD_MARK_POTENTIAL_OPENER)
        md_mark_chain_append(ctx, chain, mark_index);
}

static void
md_analyze_tilde(MD_CTX* ctx, int mark_index)
{
    /* We attempt to be Github Flavored Markdown compatible here. GFM says
     * that length of the tilde sequence is not important at all. Note that
     * implies the ctx.TILDE_OPENERS chain can have at most one item. */

    if(ctx.TILDE_OPENERS.head >= 0) {
        /* The chain already contains an opener, so we may resolve the span. */
        int opener_index = ctx.TILDE_OPENERS.head;

        md_rollback(ctx, opener_index, mark_index, MD_ROLLBACK_CROSSING);
        md_resolve_range(ctx, ctx.TILDE_OPENERS, opener_index, mark_index);
    } else {
        /* We can only be opener. */
        md_mark_chain_append(ctx, ctx.TILDE_OPENERS, mark_index);
    }
}

static void
md_analyze_dollar(MD_CTX* ctx, int mark_index)
{
    /* This should mimic the way inline equations work in LaTeX, so there
     * can only ever be one item in the chain (i.e. the dollars can't be
     * nested). This is basically the same as the md_analyze_tilde function,
     * except that we require matching openers and closers to be of the same
     * length.
     *
     * E.g.: $abc$$def$$ => abc (display equation) def (end equation) */
    if(ctx.DOLLAR_OPENERS.head >= 0) {
        /* If the potential closer has a non-matching number of $, discard */
        MD_MARK* open = &ctx.marks[ctx.DOLLAR_OPENERS.head];
        MD_MARK* close = &ctx.marks[mark_index];

        int opener_index = ctx.DOLLAR_OPENERS.head;
        md_rollback(ctx, opener_index, mark_index, MD_ROLLBACK_ALL);
        if (open.end - open.beg == close.end - close.beg) {
            /* We are the matching closer */
            md_resolve_range(ctx, ctx.DOLLAR_OPENERS, opener_index, mark_index);
        } else {
            /* We don't match the opener, so discard old opener and insert as opener */
            md_mark_chain_append(ctx, ctx.DOLLAR_OPENERS, mark_index);
        }
    } else {
        /* No unmatched openers, so we are opener */
        md_mark_chain_append(ctx, ctx.DOLLAR_OPENERS, mark_index);
    }
}

static void
md_analyze_permissive_url_autolink(MD_CTX* ctx, int mark_index)
{
    MD_MARK* opener = &ctx.marks[mark_index];
    int closer_index = mark_index + 1;
    MD_MARK* closer = &ctx.marks[closer_index];
    MD_MARK* next_resolved_mark;
    OFF off = opener.end;
    int n_dots = FALSE;
    int has_underscore_in_last_seg = FALSE;
    int has_underscore_in_next_to_last_seg = FALSE;
    int n_opened_parenthesis = 0;

    /* Check for domain. */
    while(off < ctx.size) {
        if(ctx.ISALNUM(off) || ctx.CH(off) == '-') {
            off++;
        } else if(ctx.CH(off) == '.') {
            /* We must see at least one period. */
            n_dots++;
            has_underscore_in_next_to_last_seg = has_underscore_in_last_seg;
            has_underscore_in_last_seg = FALSE;
            off++;
        } else if(ctx.CH(off) == '_') {
            /* No underscore may be present in the last two domain segments. */
            has_underscore_in_last_seg = TRUE;
            off++;
        } else {
            break;
        }
    }
    if(off > opener.end  &&  ctx.CH(off-1) == '.') {
        off--;
        n_dots--;
    }
    if(off <= opener.end || n_dots == 0 || has_underscore_in_next_to_last_seg || has_underscore_in_last_seg)
        return;

    /* Check for path. */
    next_resolved_mark = closer + 1;
    while(next_resolved_mark.ch == 'D' || !(next_resolved_mark.flags & MD_MARK_RESOLVED))
        next_resolved_mark++;
    while(off < next_resolved_mark.beg  &&  ctx.CH(off) != '<'  &&  !ctx.ISWHITESPACE(off)  &&  !ctx.ISNEWLINE(off)) {
        /* Parenthesis must be balanced. */
        if(ctx.CH(off) == '(') {
            n_opened_parenthesis++;
        } else if(ctx.CH(off) == ')') {
            if(n_opened_parenthesis > 0)
                n_opened_parenthesis--;
            else
                break;
        }

        off++;
    }
    /* These cannot be last char In such case they are more likely normal
     * punctuation. */
    if(ctx.ISANYOF(off-1, "?!.,:*_~"))
        off--;

    /* Ok. Lets call it auto-link. Adapt opener and create closer to zero
     * length so all the contents becomes the link text. */
    assert(closer.ch == 'D');
    opener.end = opener.beg;
    closer.ch = opener.ch;
    closer.beg = off;
    closer.end = off;
    md_resolve_range(ctx, null, mark_index, closer_index);
}

/* The permissive autolinks do not have to be enclosed in '<' '>' but we
 * instead impose stricter rules what is understood as an e-mail address
 * here. Actually any non-alphanumeric characters with exception of '.'
 * are prohibited both in username and after '@'. */
static void
md_analyze_permissive_email_autolink(MD_CTX* ctx, int mark_index)
{
    MD_MARK* opener = &ctx.marks[mark_index];
    int closer_index;
    MD_MARK* closer;
    OFF beg = opener.beg;
    OFF end = opener.end;
    int dot_count = 0;

    assert(ctx.CH(beg) == '@');

    /* Scan for name before '@'. */
    while(beg > 0  &&  (ctx.ISALNUM(beg-1) || ctx.ISANYOF(beg-1, ".-_+")))
        beg--;

    /* Scan for domain after '@'. */
    while(end < ctx.size  &&  (ctx.ISALNUM(end) || ctx.ISANYOF(end, ".-_"))) {
        if(ctx.CH(end) == '.')
            dot_count++;
        end++;
    }
    if(ctx.CH(end-1) == '.') {  /* Final '.' not part of it. */
        dot_count--;
        end--;
    }
    else if(ctx.ISANYOF2(end-1, '-', '_')) /* These are forbidden at the end. */
        return;
    if(ctx.CH(end-1) == '@'  ||  dot_count == 0)
        return;

    /* Ok. Lets call it auto-link. Adapt opener and create closer to zero
     * length so all the contents becomes the link text. */
    closer_index = mark_index + 1;
    closer = &ctx.marks[closer_index];
    assert(closer.ch == 'D');

    opener.beg = beg;
    opener.end = beg;
    closer.ch = opener.ch;
    closer.beg = end;
    closer.end = end;
    md_resolve_range(ctx, null, mark_index, closer_index);
}

static void
md_analyze_marks(MD_CTX* ctx, const MD_LINE* lines, int n_lines,
                 int mark_beg, int mark_end, const(CHAR)* mark_chars)
{
    int i = mark_beg;

    while(i < mark_end) {
        MD_MARK* mark = &ctx.marks[i];

        /* Skip resolved spans. */
        if(mark.flags & MD_MARK_RESOLVED) {
            if(mark.flags & MD_MARK_OPENER) {
                assert(i < mark.next);
                i = mark.next + 1;
            } else {
                i++;
            }
            continue;
        }

        /* Skip marks we do not want to deal with. */
        if(!ISANYOF_(mark.ch, mark_chars)) {
            i++;
            continue;
        }

        /* Analyze the mark. */
        switch(mark.ch) {
            case '[':   /* Pass through. */
            case '!':   /* Pass through. */
            case ']':   md_analyze_bracket(ctx, i); break;
            case '&':   md_analyze_entity(ctx, i); break;
            case '|':   md_analyze_table_cell_boundary(ctx, i); break;
            case '_':   /* Pass through. */
            case '*':   md_analyze_emph(ctx, i); break;
            case '~':   md_analyze_tilde(ctx, i); break;
            case '$':   md_analyze_dollar(ctx, i); break;
            case '.':   /* Pass through. */
            case ':':   md_analyze_permissive_url_autolink(ctx, i); break;
            case '@':   md_analyze_permissive_email_autolink(ctx, i); break;
            default:    break;
        }

        i++;
    }
}

/* Analyze marks (build ctx.marks). */
static int
md_analyze_inlines(MD_CTX* ctx, const MD_LINE* lines, int n_lines, int table_mode)
{
    int ret;

    /* Reset the previously collected stack of marks. */
    ctx.n_marks = 0;

    /* Collect all marks. */
    ret = (md_collect_marks(ctx, lines, n_lines, table_mode));
    if (ret < 0) goto abort;

    /* We analyze marks in few groups to handle their precedence. */
    /* (1) Entities; code spans; autolinks; raw HTML. */
    md_analyze_marks(ctx, lines, n_lines, 0, ctx.n_marks, "&");

    if(table_mode) {
        /* (2) Analyze table cell boundaries.
         * Note we reset ctx.TABLECELLBOUNDARIES chain prior to the call md_analyze_marks(),
         * not after, because caller may need it. */
        assert(n_lines == 1);
        ctx.TABLECELLBOUNDARIES.head = -1;
        ctx.TABLECELLBOUNDARIES.tail = -1;
        ctx.n_table_cell_boundaries = 0;
        md_analyze_marks(ctx, lines, n_lines, 0, ctx.n_marks, "|");
        return ret;
    }

    /* (3) Links. */
    md_analyze_marks(ctx, lines, n_lines, 0, ctx.n_marks, "[]!");
    ret = (md_resolve_links(ctx, lines, n_lines));
    if (ret < 0) goto abort;
    ctx.BRACKET_OPENERS.head = -1;
    ctx.BRACKET_OPENERS.tail = -1;
    ctx.unresolved_link_head = -1;
    ctx.unresolved_link_tail = -1;

    /* (4) Emphasis and strong emphasis; permissive autolinks. */
    md_analyze_link_contents(ctx, lines, n_lines, 0, ctx.n_marks);

abort:
    return ret;
}

static void
md_analyze_link_contents(MD_CTX* ctx, const MD_LINE* lines, int n_lines,
                         int mark_beg, int mark_end)
{
    md_analyze_marks(ctx, lines, n_lines, mark_beg, mark_end, "*_~$@:.");
    ctx.ASTERISK_OPENERS_extraword_mod3_0.head = -1;
    ctx.ASTERISK_OPENERS_extraword_mod3_0.tail = -1;
    ctx.ASTERISK_OPENERS_extraword_mod3_1.head = -1;
    ctx.ASTERISK_OPENERS_extraword_mod3_1.tail = -1;
    ctx.ASTERISK_OPENERS_extraword_mod3_2.head = -1;
    ctx.ASTERISK_OPENERS_extraword_mod3_2.tail = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_0.head = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_0.tail = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_1.head = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_1.tail = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_2.head = -1;
    ctx.ASTERISK_OPENERS_intraword_mod3_2.tail = -1;
    ctx.UNDERSCORE_OPENERS.head = -1;
    ctx.UNDERSCORE_OPENERS.tail = -1;
    ctx.TILDE_OPENERS.head = -1;
    ctx.TILDE_OPENERS.tail = -1;
    ctx.DOLLAR_OPENERS.head = -1;
    ctx.DOLLAR_OPENERS.tail = -1;
}

static int
md_enter_leave_span_a(MD_CTX* ctx, int enter, MD_SPANTYPE type,
                      const(CHAR)* dest, SZ dest_size, int prohibit_escapes_in_dest,
                      const(CHAR)* title, SZ title_size)
{
    MD_ATTRIBUTE_BUILD href_build = MD_ATTRIBUTE_BUILD.init;
    MD_ATTRIBUTE_BUILD title_build = MD_ATTRIBUTE_BUILD.init;
    MD_SPAN_A_DETAIL det;
    int ret = 0;

    /* Note we here rely on fact that MD_SPAN_A_DETAIL and
     * MD_SPAN_IMG_DETAIL are binary-compatible. */
    memset(&det, 0, MD_SPAN_A_DETAIL.sizeof);
    ret = (md_build_attribute(ctx, dest, dest_size,
                    (prohibit_escapes_in_dest ? MD_BUILD_ATTR_NO_ESCAPES : 0),
                    &det.href, &href_build));
    if (ret < 0) goto abort;
    ret = (md_build_attribute(ctx, title, title_size, 0, &det.title, &title_build));
    if (ret < 0) goto abort;

    if(enter)
    {
        ret = MD_ENTER_SPAN(ctx, type, &det);
        if (ret != 0) goto abort;
    }
    else
    {
        ret = MD_LEAVE_SPAN(ctx, type, &det);
        if (ret != 0) goto abort;
    }

abort:
    md_free_attribute(ctx, &href_build);
    md_free_attribute(ctx, &title_build);
    return ret;
}

/* Render the output, accordingly to the analyzed ctx.marks. */
static int
md_process_inlines(MD_CTX* ctx, const MD_LINE* lines, int n_lines)
{
    MD_TEXTTYPE text_type;
    const(MD_LINE)* line = lines;
    MD_MARK* prev_mark = null;
    MD_MARK* mark;
    OFF off = lines[0].beg;
    OFF end = lines[n_lines-1].end;
    int enforce_hardbreak = 0;
    int ret = 0;

    /* Find first resolved mark. Note there is always at least one resolved
     * mark,  the dummy last one after the end of the latest line we actually
     * never really reach. This saves us of a lot of special checks and cases
     * in this function. */
    mark = ctx.marks;
    while(!(mark.flags & MD_MARK_RESOLVED))
        mark++;

    text_type = MD_TEXT_NORMAL;

    while(1) {
        /* Process the text up to the next mark or end-of-line. */
        OFF tmp = (line.end < mark.beg ? line.end : mark.beg);
        if(tmp > off) {
            ret = MD_TEXT(ctx, text_type, ctx.STR(off), tmp - off);
            if (ret != 0) goto abort;
            off = tmp;
        }

        /* If reached the mark, process it and move to next one. */
        if(off >= mark.beg) {
            switch(mark.ch) {
                case '\\':      /* Backslash escape. */
                    if(ctx.ISNEWLINE(mark.beg+1))
                        enforce_hardbreak = 1;
                    else
                    {
                        ret = MD_TEXT(ctx, text_type, ctx.STR(mark.beg+1), 1);
                        if (ret != 0) goto abort;
                    }
                    break;

                case ' ':       /* Non-trivial space. */
                    ret = MD_TEXT(ctx, text_type, " ", 1);
                    if (ret != 0) goto abort;
                    break;

                case '`':       /* Code span. */
                    if(mark.flags & MD_MARK_OPENER) {
                        ret = MD_ENTER_SPAN(ctx, MD_SPAN_CODE, null);
                        if (ret != 0) goto abort;
                        text_type = MD_TEXT_CODE;
                    } else {
                        ret = MD_LEAVE_SPAN(ctx, MD_SPAN_CODE, null);
                        if (ret != 0) goto abort;
                        text_type = MD_TEXT_NORMAL;
                    }
                    break;

                case '_':
                case '*':       /* Emphasis, strong emphasis. */
                    if(mark.flags & MD_MARK_OPENER) {
                        if((mark.end - off) % 2) {
                            ret = MD_ENTER_SPAN(ctx, MD_SPAN_EM, null);
                            if (ret != 0) goto abort;
                            off++;
                        }
                        while(off + 1 < mark.end) {
                            ret = MD_ENTER_SPAN(ctx, MD_SPAN_STRONG, null);
                            if (ret != 0) goto abort;
                            off += 2;
                        }
                    } else {
                        while(off + 1 < mark.end) {
                            ret = MD_LEAVE_SPAN(ctx, MD_SPAN_STRONG, null);
                            if (ret != 0) goto abort;
                            off += 2;
                        }
                        if((mark.end - off) % 2) {
                            ret = MD_LEAVE_SPAN(ctx, MD_SPAN_EM, null);
                            if (ret != 0) goto abort;
                            off++;
                        }
                    }
                    break;

                case '~':
                    if(mark.flags & MD_MARK_OPENER)
                    {
                        ret = MD_ENTER_SPAN(ctx, MD_SPAN_DEL, null);
                        if (ret != 0) goto abort;
                    }
                    else
                    {
                        ret = MD_LEAVE_SPAN(ctx, MD_SPAN_DEL, null);
                        if (ret != 0) goto abort;
                    }
                    break;

                case '$':
                    if(mark.flags & MD_MARK_OPENER) {
                        ret = MD_ENTER_SPAN(ctx, (mark.end - off) % 2 ? MD_SPAN_LATEXMATH : MD_SPAN_LATEXMATH_DISPLAY, null);
                        if (ret != 0) goto abort;
                        text_type = MD_TEXT_LATEXMATH;
                    } else {
                        ret = MD_LEAVE_SPAN(ctx, (mark.end - off) % 2 ? MD_SPAN_LATEXMATH : MD_SPAN_LATEXMATH_DISPLAY, null);
                        if (ret != 0) goto abort;
                        text_type = MD_TEXT_NORMAL;
                    }
                    break;

                case '[':       /* Link, image. */
                case '!':
                case ']':
                {
                    const MD_MARK* opener = (mark.ch != ']' ? mark : &ctx.marks[mark.prev]);
                    const MD_MARK* dest_mark = opener+1;
                    const MD_MARK* title_mark = opener+2;

                    assert(dest_mark.ch == 'D');
                    assert(title_mark.ch == 'D');

                    ret = (md_enter_leave_span_a(ctx, (mark.ch != ']') ? 1 : 0,
                                (opener.ch == '!' ? MD_SPAN_IMG : MD_SPAN_A),
                                ctx.STR(dest_mark.beg), dest_mark.end - dest_mark.beg, FALSE,
                                cast(char*) md_mark_get_ptr(ctx, cast(int)(title_mark - ctx.marks)), title_mark.prev));
                    if (ret < 0) goto abort;

                    /* link/image closer may span multiple lines. */
                    if(mark.ch == ']') {
                        while(mark.end > line.end)
                            line++;
                    }

                    break;
                }

                case '<':
                case '>':       /* Autolink or raw HTML. */
                    if(!(mark.flags & MD_MARK_AUTOLINK)) {
                        /* Raw HTML. */
                        if(mark.flags & MD_MARK_OPENER)
                            text_type = MD_TEXT_HTML;
                        else
                            text_type = MD_TEXT_NORMAL;
                        break;
                    }
                    /* Pass through, if auto-link. */
                    goto case '.';

                case '@':       /* Permissive e-mail autolink. */
                case ':':       /* Permissive URL autolink. */
                case '.':       /* Permissive WWW autolink. */
                {
                    MD_MARK* opener = ((mark.flags & MD_MARK_OPENER) ? mark : &ctx.marks[mark.prev]);
                    MD_MARK* closer = &ctx.marks[opener.next];
                    const(CHAR)* dest = ctx.STR(opener.end);
                    SZ dest_size = closer.beg - opener.end;

                    /* For permissive auto-links we do not know closer mark
                     * position at the time of md_collect_marks(), therefore
                     * it can be out-of-order in ctx.marks[].
                     *
                     * With this flag, we make sure that we output the closer
                     * only if we processed the opener. */
                    if(mark.flags & MD_MARK_OPENER)
                        closer.flags |= MD_MARK_VALIDPERMISSIVEAUTOLINK;

                    if(opener.ch == '@' || opener.ch == '.') {
                        dest_size += 7;
                        ret = MD_TEMP_BUFFER(ctx, dest_size * CHAR.sizeof);
                        if (ret < 0) goto abort;
                        memcpy(ctx.buffer,
                                (opener.ch == '@' ? "mailto:" : "http://").ptr,
                                7 * CHAR.sizeof);
                        memcpy(ctx.buffer + 7, dest, (dest_size-7) * CHAR.sizeof);
                        dest = ctx.buffer;
                    }

                    if(closer.flags & MD_MARK_VALIDPERMISSIVEAUTOLINK)
                    {
                        ret = (md_enter_leave_span_a(ctx, (mark.flags & MD_MARK_OPENER),
                                    MD_SPAN_A, dest, dest_size, TRUE, null, 0));
                        if (ret < 0) goto abort;
                    }
                    break;
                }

                case '&':       /* Entity. */
                    ret = MD_TEXT(ctx, MD_TEXT_ENTITY, ctx.STR(mark.beg), mark.end - mark.beg);
                    if (ret != 0) goto abort;
                    break;

                case '\0':
                    ret = MD_TEXT(ctx, MD_TEXT_NULLCHAR, "", 1);
                    if (ret != 0) goto abort;
                    break;

                case 127:
                    goto abort;

                default:
                    break;
            }

            off = mark.end;

            /* Move to next resolved mark. */
            prev_mark = mark;
            mark++;
            while(!(mark.flags & MD_MARK_RESOLVED)  ||  mark.beg < off)
                mark++;
        }

        /* If reached end of line, move to next one. */
        if(off >= line.end) {
            /* If it is the last line, we are done. */
            if(off >= end)
                break;

            if(text_type == MD_TEXT_CODE || text_type == MD_TEXT_LATEXMATH) {
                OFF tmp2;

                assert(prev_mark != null);
                assert(ISANYOF2_(prev_mark.ch, '`', '$')  &&  (prev_mark.flags & MD_MARK_OPENER));
                assert(ISANYOF2_(mark.ch, '`', '$')  &&  (mark.flags & MD_MARK_CLOSER));

                /* Inside a code span, trailing line whitespace has to be
                 * outputted. */
                tmp2 = off;
                while(off < ctx.size  &&  ctx.ISBLANK(off))
                    off++;
                if(off > tmp2)
                {
                    ret = MD_TEXT(ctx, text_type, ctx.STR(tmp2), off-tmp2);
                    if (ret != 0) goto abort;
                }

                /* and new lines are transformed into single spaces. */
                if(prev_mark.end < off  &&  off < mark.beg)
                {
                    ret = MD_TEXT(ctx, text_type, " ", 1);
                    if (ret != 0) goto abort;
                }
            } else if(text_type == MD_TEXT_HTML) {
                /* Inside raw HTML, we output the new line verbatim, including
                 * any trailing spaces. */
                OFF tmp2 = off;

                while(tmp2 < end  &&  ctx.ISBLANK(tmp2))
                    tmp2++;
                if(tmp2 > off)
                {
                    ret = MD_TEXT(ctx, MD_TEXT_HTML, ctx.STR(off), tmp2 - off);
                    if (ret != 0) goto abort;
                }
                ret = MD_TEXT(ctx, MD_TEXT_HTML, "\n", 1);
                if (ret != 0) goto abort;
            } else {
                /* Output soft or hard line break. */
                MD_TEXTTYPE break_type = MD_TEXT_SOFTBR;

                if(text_type == MD_TEXT_NORMAL) {
                    if(enforce_hardbreak)
                        break_type = MD_TEXT_BR;
                    else if((ctx.CH(line.end) == ' ' && ctx.CH(line.end+1) == ' '))
                        break_type = MD_TEXT_BR;
                }

                ret = MD_TEXT(ctx, break_type, "\n", 1);
                if (ret != 0) goto abort;
            }

            /* Move to the next line. */
            line++;
            off = line.beg;

            enforce_hardbreak = 0;
        }
    }

abort:
    return ret;
}


/***************************
 ***  Processing Tables  ***
 ***************************/

void md_analyze_table_alignment(MD_CTX* ctx, OFF beg, OFF end, MD_ALIGN* align_, int n_align)
{
    static immutable MD_ALIGN[] align_map =
    [
        MD_ALIGN_DEFAULT,
        MD_ALIGN_LEFT,
        MD_ALIGN_RIGHT,
        MD_ALIGN_CENTER
    ];
    OFF off = beg;

    while(n_align > 0) {
        int index = 0;  /* index into align_map[] */

        while(ctx.CH(off) != '-')
            off++;
        if(off > beg  &&  ctx.CH(off-1) == ':')
            index |= 1;
        while(off < end  &&  ctx.CH(off) == '-')
            off++;
        if(off < end  &&  ctx.CH(off) == ':')
            index |= 2;

        *align_ = align_map[index];
        align_++;
        n_align--;
    }

}

int md_process_table_cell(MD_CTX* ctx, MD_BLOCKTYPE cell_type, MD_ALIGN align_, OFF beg, OFF end)
{
    MD_LINE line;
    MD_BLOCK_TD_DETAIL det;
    int ret = 0;

    while(beg < end  &&  ctx.ISWHITESPACE(beg))
        beg++;
    while(end > beg  &&  ctx.ISWHITESPACE(end-1))
        end--;

    det.align_ = align_;
    line.beg = beg;
    line.end = end;

    ret = MD_ENTER_BLOCK(ctx, cell_type, &det);
    if (ret != 0) goto abort;
    ret = (md_process_normal_block_contents(ctx, &line, 1));
    if (ret < 0) goto abort;
    ret = MD_LEAVE_BLOCK(ctx, cell_type, &det);
    if (ret != 0) goto abort;

abort:
    return ret;
}

int md_process_table_row(MD_CTX* ctx, MD_BLOCKTYPE cell_type, OFF beg, OFF end,
                         const MD_ALIGN* align_, int col_count)
{
    MD_LINE line;
    OFF* pipe_offs = null;
    int i, j, n;
    int ret = 0;

    line.beg = beg;
    line.end = end;

    /* Break the line into table cells by identifying pipe characters who
     * form the cell boundary. */
    ret = (md_analyze_inlines(ctx, &line, 1, TRUE));
    if (ret < 0) goto abort;

    /* We have to remember the cell boundaries in local buffer because
     * ctx.marks[] shall be reused during cell contents processing. */
    n = ctx.n_table_cell_boundaries;
    pipe_offs = cast(OFF*) malloc(n * OFF.sizeof);
    if(pipe_offs == null) {
        ctx.MD_LOG("malloc() failed.");
        ret = -1;
        goto abort;
    }
    for(i = ctx.TABLECELLBOUNDARIES.head, j = 0; i >= 0; i = ctx.marks[i].next) {
        MD_MARK* mark = &ctx.marks[i];
        pipe_offs[j++] = mark.beg;
    }

    /* Process cells. */
    ret = MD_ENTER_BLOCK(ctx, MD_BLOCK_TR, null);
    if (ret != 0) goto abort;

    j = 0;
    if(beg < pipe_offs[0]  &&  j < col_count)
    {
        ret = (md_process_table_cell(ctx, cell_type, align_[j++], beg, pipe_offs[0]));
        if (ret < 0) goto abort;
    }
    for(i = 0; i < n-1  &&  j < col_count; i++)
    {
        ret = (md_process_table_cell(ctx, cell_type, align_[j++], pipe_offs[i]+1, pipe_offs[i+1]));
        if (ret < 0) goto abort;
    }
    if(pipe_offs[n-1] < end-1  &&  j < col_count)
    {
        ret = (md_process_table_cell(ctx, cell_type, align_[j++], pipe_offs[n-1]+1, end));
        if (ret < 0) goto abort;
    }
    /* Make sure we call enough table cells even if the current table contains
     * too few of them. */
    while(j < col_count)
    {
        ret = (md_process_table_cell(ctx, cell_type, align_[j++], 0, 0));
        if (ret < 0) goto abort;
    }

    ret = MD_LEAVE_BLOCK(ctx, MD_BLOCK_TR, null);
    if (ret != 0) goto abort;

abort:
    free(pipe_offs);

    /* Free any temporary memory blocks stored within some dummy marks. */
    for(i = ctx.PTR_CHAIN.head; i >= 0; i = ctx.marks[i].next)
        free(md_mark_get_ptr(ctx, i));
    ctx.PTR_CHAIN.head = -1;
    ctx.PTR_CHAIN.tail = -1;

    return ret;
}

int md_process_table_block_contents(MD_CTX* ctx, int col_count, const MD_LINE* lines, int n_lines)
{
    MD_ALIGN* align_;
    int i;
    int ret = 0;

    /* At least two lines have to be present: The column headers and the line
     * with the underlines. */
    assert(n_lines >= 2);

    align_ = cast(MD_ALIGN*) malloc(col_count * MD_ALIGN.sizeof);
    if(align_ == null) {
        ctx.MD_LOG("malloc() failed.");
        ret = -1;
        goto abort;
    }

    md_analyze_table_alignment(ctx, lines[1].beg, lines[1].end, align_, col_count);

    ret = MD_ENTER_BLOCK(ctx, MD_BLOCK_THEAD, null);
    if (ret != 0) goto abort;
    ret = (md_process_table_row(ctx, MD_BLOCK_TH,
                        lines[0].beg, lines[0].end, align_, col_count));
    if (ret < 0) goto abort;
    ret = MD_LEAVE_BLOCK(ctx, MD_BLOCK_THEAD, null);
    if (ret != 0) goto abort;

    ret = MD_ENTER_BLOCK(ctx, MD_BLOCK_TBODY, null);
    if (ret != 0) goto abort;
    for(i = 2; i < n_lines; i++) {
        ret = (md_process_table_row(ctx, MD_BLOCK_TD,
                        lines[i].beg, lines[i].end, align_, col_count));
        if (ret < 0) goto abort;
    }
    ret = MD_LEAVE_BLOCK(ctx, MD_BLOCK_TBODY, null);
    if (ret != 0) goto abort;

abort:
    free(align_);
    return ret;
}

int md_is_table_row(MD_CTX* ctx, OFF beg, OFF* p_end)
{
    MD_LINE line;
    int i;
    int ret = FALSE;

    line.beg = beg;
    line.end = beg;

    /* Find end of line. */
    while(line.end < ctx.size  &&  !ctx.ISNEWLINE(line.end))
        line.end++;

    ret = (md_analyze_inlines(ctx, &line, 1, TRUE));
    if (ret < 0) goto abort;

    if(ctx.TABLECELLBOUNDARIES.head >= 0) {
        if(p_end != null)
            *p_end = line.end;
        ret = TRUE;
    }

abort:
    /* Free any temporary memory blocks stored within some dummy marks. */
    for(i = ctx.PTR_CHAIN.head; i >= 0; i = ctx.marks[i].next)
        free(md_mark_get_ptr(ctx, i));
    ctx.PTR_CHAIN.head = -1;
    ctx.PTR_CHAIN.tail = -1;

    return ret;
}


/**************************
 ***  Processing Block  ***
 **************************/

enum MD_BLOCK_CONTAINER_OPENER   = 0x01;
enum MD_BLOCK_CONTAINER_CLOSER   = 0x02;
enum MD_BLOCK_CONTAINER          = (MD_BLOCK_CONTAINER_OPENER | MD_BLOCK_CONTAINER_CLOSER);
enum MD_BLOCK_LOOSE_LIST         = 0x04;
enum MD_BLOCK_SETEXT_HEADER      = 0x08;

struct MD_BLOCK
{
nothrow:
@nogc:
    ubyte type_;
    ubyte flags_;
    ushort data_;

    MD_BLOCKTYPE type() const { return type_; }
    void type(MD_BLOCKTYPE value) { type_ = cast(ubyte)value; }

    uint flags() const { return flags_; }
    void flags(uint value) { flags_ = cast(ubyte)value; }

    /* MD_BLOCK_H:      Header level (1 - 6)
     * MD_BLOCK_CODE:   Non-zero if fenced, zero if indented.
     * MD_BLOCK_LI:     Task mark character (0 if not task list item, 'x', 'X' or ' ').
     * MD_BLOCK_TABLE:  Column count (as determined by the table underline).
     */
    uint data() const { return data_; }
    void data(uint value) { data_ = cast(ubyte)value; }

    /* Leaf blocks:     Count of lines (MD_LINE or MD_VERBATIMLINE) on the block.
     * MD_BLOCK_LI:     Task mark offset in the input doc.
     * MD_BLOCK_OL:     Start item number.
     */
    uint n_lines;
}

static assert(MD_BLOCK.sizeof == 8);

struct MD_CONTAINER
{
nothrow:
@nogc:

    CHAR ch;

    ubyte is_loose_;
    ubyte is_task_;

    uint is_loose() { return is_loose_; }
    void is_loose(uint value) { is_loose_ = cast(ubyte)value; }

    uint is_task() { return is_task_; }
    void is_task(uint value) { is_task_ = cast(ubyte)value; }

    uint start;
    uint mark_indent;
    uint contents_indent;
    OFF block_byte_off;
    OFF task_mark_off;
}


int md_process_normal_block_contents(MD_CTX* ctx, const MD_LINE* lines, int n_lines)
{
    int i;
    int ret;

    ret = (md_analyze_inlines(ctx, lines, n_lines, FALSE));
    if (ret < 0) goto abort;
    ret = (md_process_inlines(ctx, lines, n_lines));
    if (ret < 0) goto abort;

abort:
    /* Free any temporary memory blocks stored within some dummy marks. */
    for(i = ctx.PTR_CHAIN.head; i >= 0; i = ctx.marks[i].next)
        free(md_mark_get_ptr(ctx, i));
    ctx.PTR_CHAIN.head = -1;
    ctx.PTR_CHAIN.tail = -1;

    return ret;
}

int md_process_verbatim_block_contents(MD_CTX* ctx, MD_TEXTTYPE text_type, const MD_VERBATIMLINE* lines, int n_lines)
{
    static immutable string indent_chunk_str = "                ";

    int i;
    int ret = 0;

    for(i = 0; i < n_lines; i++) {
        const MD_VERBATIMLINE* line = &lines[i];
        int indent = line.indent;

        assert(indent >= 0);

        /* Output code indentation. */
        while(indent > cast(int)(indent_chunk_str.length)) {
            ret = MD_TEXT(ctx, text_type, indent_chunk_str.ptr, cast(SZ)(indent_chunk_str.length));
            if (ret != 0) goto abort;
            indent -= indent_chunk_str.length;
        }
        if(indent > 0)
        {
            ret = MD_TEXT(ctx, text_type, indent_chunk_str.ptr, indent);
            if (ret != 0) goto abort;
        }

        /* Output the code line itself. */
        ret = MD_TEXT_INSECURE(ctx, text_type, ctx.STR(line.beg), line.end - line.beg);
        if (ret != 0) goto abort;

        /* Enforce end-of-line. */
        ret = MD_TEXT(ctx, text_type, "\n", 1);
        if (ret != 0) goto abort;
    }

abort:
    return ret;
}

static int
md_process_code_block_contents(MD_CTX* ctx, int is_fenced, const(MD_VERBATIMLINE)* lines, int n_lines)
{
    if(is_fenced) {
        /* Skip the first line in case of fenced code: It is the fence.
         * (Only the starting fence is present due to logic in md_analyze_line().) */
        lines++;
        n_lines--;
    } else {
        /* Ignore blank lines at start/end of indented code block. */
        while(n_lines > 0  &&  lines[0].beg == lines[0].end) {
            lines++;
            n_lines--;
        }
        while(n_lines > 0  &&  lines[n_lines-1].beg == lines[n_lines-1].end) {
            n_lines--;
        }
    }

    if(n_lines == 0)
        return 0;

    return md_process_verbatim_block_contents(ctx, MD_TEXT_CODE, lines, n_lines);
}

int md_setup_fenced_code_detail(MD_CTX* ctx, const(MD_BLOCK)* block, MD_BLOCK_CODE_DETAIL* det,
                                MD_ATTRIBUTE_BUILD* info_build, MD_ATTRIBUTE_BUILD* lang_build)
{
    const(MD_VERBATIMLINE)* fence_line = cast(const(MD_VERBATIMLINE)*)(block + 1);
    OFF beg = fence_line.beg;
    OFF end = fence_line.end;
    OFF lang_end;
    CHAR fence_ch = ctx.CH(fence_line.beg);
    int ret = 0;

    /* Skip the fence itself. */
    while(beg < ctx.size  &&  ctx.CH(beg) == fence_ch)
        beg++;
    /* Trim initial spaces. */
    while(beg < ctx.size  &&  ctx.CH(beg) == ' ')
        beg++;

    /* Trim trailing spaces. */
    while(end > beg  &&  ctx.CH(end-1) == ' ')
        end--;

    /* Build info string attribute. */
    ret = (md_build_attribute(ctx, ctx.STR(beg), end - beg, 0, &det.info, info_build));
    if (ret < 0) goto abort;

    /* Build info string attribute. */
    lang_end = beg;
    while(lang_end < end  &&  !ctx.ISWHITESPACE(lang_end))
        lang_end++;
    ret = (md_build_attribute(ctx, ctx.STR(beg), lang_end - beg, 0, &det.lang, lang_build));
    if (ret < 0) goto abort;

    det.fence_char = fence_ch;

abort:
    return ret;
}

static int
md_process_leaf_block(MD_CTX* ctx, const MD_BLOCK* block)
{
    static union HeaderOrCode
    {
        MD_BLOCK_H_DETAIL header;
        MD_BLOCK_CODE_DETAIL code;
    }
    HeaderOrCode det;
    MD_ATTRIBUTE_BUILD info_build;
    MD_ATTRIBUTE_BUILD lang_build;
    int is_in_tight_list;
    int clean_fence_code_detail = FALSE;
    int ret = 0;

    memset(&det, 0, det.sizeof);

    if(ctx.n_containers == 0)
        is_in_tight_list = FALSE;
    else
        is_in_tight_list = !ctx.containers[ctx.n_containers-1].is_loose;

    switch(block.type)
    {
        case MD_BLOCK_H:
            det.header.level = block.data;
            break;

        case MD_BLOCK_CODE:
            /* For fenced code block, we may need to set the info string. */
            if(block.data != 0) {
                memset(&det.code, 0, MD_BLOCK_CODE_DETAIL.sizeof);
                clean_fence_code_detail = TRUE;
                ret = (md_setup_fenced_code_detail(ctx, block, &det.code, &info_build, &lang_build));
                if (ret < 0) goto abort;
            }
            break;

        default:
            /* Noop. */
            break;
    }

    if(!is_in_tight_list  ||  block.type != MD_BLOCK_P)
    {
        ret = MD_ENTER_BLOCK(ctx, block.type, cast(void*) &det);
        if (ret != 0) goto abort;
    }

    /* Process the block contents accordingly to is type. */
    switch(block.type) {
        case MD_BLOCK_HR:
            /* noop */
            break;

        case MD_BLOCK_CODE:
            ret = (md_process_code_block_contents(ctx, (block.data != 0),
                            cast(const(MD_VERBATIMLINE)*)(block + 1), block.n_lines));
            if (ret < 0) goto abort;
            break;

        case MD_BLOCK_HTML:
            ret = (md_process_verbatim_block_contents(ctx, MD_TEXT_HTML,
                            cast(const(MD_VERBATIMLINE)*)(block + 1), block.n_lines));
            if (ret < 0) goto abort;
            break;

        case MD_BLOCK_TABLE:
            ret = (md_process_table_block_contents(ctx, block.data,
                            cast(const(MD_LINE)*)(block + 1), block.n_lines));
            if (ret < 0) goto abort;
            break;

        default:
            ret = (md_process_normal_block_contents(ctx,
                            cast(const(MD_LINE)*)(block + 1), block.n_lines));
            if (ret < 0) goto abort;
            break;
    }

    if(!is_in_tight_list  ||  block.type != MD_BLOCK_P)
    {
        ret = MD_LEAVE_BLOCK(ctx, block.type, cast(void*) &det);
        if (ret != 0) goto abort;
    }

abort:
    if(clean_fence_code_detail) {
        md_free_attribute(ctx, &info_build);
        md_free_attribute(ctx, &lang_build);
    }
    return ret;
}

int md_process_all_blocks(MD_CTX* ctx)
{
    int byte_off = 0;
    int ret = 0;

    /* ctx.containers now is not needed for detection of lists and list items
     * so we reuse it for tracking what lists are loose or tight. We rely
     * on the fact the vector is large enough to hold the deepest nesting
     * level of lists. */
    ctx.n_containers = 0;

    while(byte_off < ctx.n_block_bytes) {
        MD_BLOCK* block = cast(MD_BLOCK*)(cast(char*)ctx.block_bytes + byte_off);
        static union Det
        {
            MD_BLOCK_UL_DETAIL ul;
            MD_BLOCK_OL_DETAIL ol;
            MD_BLOCK_LI_DETAIL li;
        }

        Det det;

        switch(block.type) {
            case MD_BLOCK_UL:
                det.ul.is_tight = (block.flags & MD_BLOCK_LOOSE_LIST) ? FALSE : TRUE;
                det.ul.mark = cast(CHAR) block.data;
                break;

            case MD_BLOCK_OL:
                det.ol.start = block.n_lines;
                det.ol.is_tight =  (block.flags & MD_BLOCK_LOOSE_LIST) ? FALSE : TRUE;
                det.ol.mark_delimiter = cast(CHAR) block.data;
                break;

            case MD_BLOCK_LI:
                det.li.is_task = (block.data != 0);
                det.li.task_mark = cast(CHAR) block.data;
                det.li.task_mark_offset = cast(OFF) block.n_lines;
                break;

            default:
                /* noop */
                break;
        }

        if(block.flags & MD_BLOCK_CONTAINER) {
            if(block.flags & MD_BLOCK_CONTAINER_CLOSER) {
                ret = MD_LEAVE_BLOCK(ctx, block.type, &det);
                if (ret != 0) goto abort;

                if(block.type == MD_BLOCK_UL || block.type == MD_BLOCK_OL || block.type == MD_BLOCK_QUOTE)
                    ctx.n_containers--;
            }

            if(block.flags & MD_BLOCK_CONTAINER_OPENER) {
                ret = MD_ENTER_BLOCK(ctx, block.type, &det);
                if (ret != 0) goto abort;

                if(block.type == MD_BLOCK_UL || block.type == MD_BLOCK_OL) {
                    ctx.containers[ctx.n_containers].is_loose = (block.flags & MD_BLOCK_LOOSE_LIST);
                    ctx.n_containers++;
                } else if(block.type == MD_BLOCK_QUOTE) {
                    /* This causes that any text in a block quote, even if
                     * nested inside a tight list item, is wrapped with
                     * <p>...</p>. */
                    ctx.containers[ctx.n_containers].is_loose = TRUE;
                    ctx.n_containers++;
                }
            }
        } else {
            ret = (md_process_leaf_block(ctx, block));
            if (ret < 0) goto abort;

            if(block.type == MD_BLOCK_CODE || block.type == MD_BLOCK_HTML)
                byte_off += block.n_lines * MD_VERBATIMLINE.sizeof;
            else
                byte_off += block.n_lines * MD_LINE.sizeof;
        }

        byte_off += MD_BLOCK.sizeof;
    }

    ctx.n_block_bytes = 0;

abort:
    return ret;
}


/************************************
 ***  Grouping Lines into Blocks  ***
 ************************************/

static void*
md_push_block_bytes(MD_CTX* ctx, int n_bytes)
{
    void* ptr;

    if(ctx.n_block_bytes + n_bytes > ctx.alloc_block_bytes) {
        void* new_block_bytes;

        ctx.alloc_block_bytes = (ctx.alloc_block_bytes > 0 ? ctx.alloc_block_bytes * 2 : 512);
        new_block_bytes = realloc_safe(ctx.block_bytes, ctx.alloc_block_bytes);
        if(new_block_bytes == null) {
            ctx.MD_LOG("realloc() failed.");
            return null;
        }

        /* Fix the .current_block after the reallocation. */
        if(ctx.current_block != null) {
            OFF off_current_block = cast(uint)( cast(char*) ctx.current_block - cast(char*) ctx.block_bytes );
            ctx.current_block = cast(MD_BLOCK*) (cast(char*) new_block_bytes + off_current_block);
        }

        ctx.block_bytes = new_block_bytes;
    }

    ptr = cast(char*)ctx.block_bytes + ctx.n_block_bytes;
    ctx.n_block_bytes += n_bytes;
    return ptr;
}

static int
md_start_new_block(MD_CTX* ctx, const MD_LINE_ANALYSIS* line)
{
    MD_BLOCK* block;

    assert(ctx.current_block == null);

    block = cast(MD_BLOCK*) md_push_block_bytes(ctx, MD_BLOCK.sizeof);
    if(block == null)
        return -1;

    switch(line.type) {
        case MD_LINE_HR:
            block.type = MD_BLOCK_HR;
            break;

        case MD_LINE_ATXHEADER:
        case MD_LINE_SETEXTHEADER:
            block.type = MD_BLOCK_H;
            break;

        case MD_LINE_FENCEDCODE:
        case MD_LINE_INDENTEDCODE:
            block.type = MD_BLOCK_CODE;
            break;

        case MD_LINE_TEXT:
            block.type = MD_BLOCK_P;
            break;

        case MD_LINE_HTML:
            block.type = MD_BLOCK_HTML;
            break;

        case MD_LINE_BLANK:
        case MD_LINE_SETEXTUNDERLINE:
        case MD_LINE_TABLEUNDERLINE:
        default:
            assert(false);
    }

    block.flags = 0;
    block.data = line.data;
    block.n_lines = 0;

    ctx.current_block = block;
    return 0;
}

/* Eat from start of current (textual) block any reference definitions and
 * remember them so we can resolve any links referring to them.
 *
 * (Reference definitions can only be at start of it as they cannot break
 * a paragraph.)
 */
int md_consume_link_reference_definitions(MD_CTX* ctx)
{
    MD_LINE* lines = cast(MD_LINE*) (ctx.current_block + 1);
    int n_lines = ctx.current_block.n_lines;
    int n = 0;

    /* Compute how many lines at the start of the block form one or more
     * reference definitions. */
    while(n < n_lines) {
        int n_link_ref_lines;

        n_link_ref_lines = md_is_link_reference_definition(ctx,
                                    lines + n, n_lines - n);
        /* Not a reference definition? */
        if(n_link_ref_lines == 0)
            break;

        /* We fail if it is the ref. def. but it could not be stored due
         * a memory allocation error. */
        if(n_link_ref_lines < 0)
            return -1;

        n += n_link_ref_lines;
    }

    /* If there was at least one reference definition, we need to remove
     * its lines from the block, or perhaps even the whole block. */
    if(n > 0) {
        if(n == n_lines) {
            /* Remove complete block. */
            ctx.n_block_bytes -= n * MD_LINE.sizeof;
            ctx.n_block_bytes -= MD_BLOCK.sizeof;
            ctx.current_block = null;
        } else {
            /* Remove just some initial lines from the block. */
            memmove(lines, lines + n, (n_lines - n) * MD_LINE.sizeof);
            ctx.current_block.n_lines -= n;
            ctx.n_block_bytes -= n * MD_LINE.sizeof;
        }
    }

    return 0;
}

static int
md_end_current_block(MD_CTX* ctx)
{
    int ret = 0;

    if(ctx.current_block == null)
        return ret;

    /* Check whether there is a reference definition. (We do this here instead
     * of in md_analyze_line() because reference definition can take multiple
     * lines.) */
    if(ctx.current_block.type == MD_BLOCK_P  ||
       (ctx.current_block.type == MD_BLOCK_H  &&  (ctx.current_block.flags & MD_BLOCK_SETEXT_HEADER)))
    {
        MD_LINE* lines = cast(MD_LINE*) (ctx.current_block + 1);
        if(ctx.CH(lines[0].beg) == '[') {
            ret = (md_consume_link_reference_definitions(ctx));
            if (ret < 0) goto abort;
            if(ctx.current_block == null)
                return ret;
        }
    }

    if(ctx.current_block.type == MD_BLOCK_H  &&  (ctx.current_block.flags & MD_BLOCK_SETEXT_HEADER)) {
        int n_lines = ctx.current_block.n_lines;

        if(n_lines > 1) {
            /* Get rid of the underline. */
            ctx.current_block.n_lines--;
            ctx.n_block_bytes -= MD_LINE.sizeof;
        } else {
            /* Only the underline has left after eating the ref. defs.
             * Keep the line as beginning of a new ordinary paragraph. */
            ctx.current_block.type = MD_BLOCK_P;
            return 0;
        }
    }

    /* Mark we are not building any block anymore. */
    ctx.current_block = null;

abort:
    return ret;
}

static int
md_add_line_into_current_block(MD_CTX* ctx, const MD_LINE_ANALYSIS* analysis)
{
    assert(ctx.current_block != null);

    if(ctx.current_block.type == MD_BLOCK_CODE || ctx.current_block.type == MD_BLOCK_HTML) {
        MD_VERBATIMLINE* line;

        line = cast(MD_VERBATIMLINE*) md_push_block_bytes(ctx, MD_VERBATIMLINE.sizeof);
        if(line == null)
            return -1;

        line.indent = analysis.indent;
        line.beg = analysis.beg;
        line.end = analysis.end;
    } else {
        MD_LINE* line;

        line = cast(MD_LINE*) md_push_block_bytes(ctx, MD_LINE.sizeof);
        if(line == null)
            return -1;

        line.beg = analysis.beg;
        line.end = analysis.end;
    }
    ctx.current_block.n_lines++;

    return 0;
}

static int
md_push_container_bytes(MD_CTX* ctx, MD_BLOCKTYPE type, uint start,
                        uint data, uint flags)
{
    MD_BLOCK* block;
    int ret = 0;

    ret = (md_end_current_block(ctx));
    if (ret < 0) goto abort;

    block = cast(MD_BLOCK*) md_push_block_bytes(ctx, MD_BLOCK.sizeof);
    if(block == null)
        return -1;

    block.type = type;
    block.flags = flags;
    block.data = data;
    block.n_lines = start;

abort:
    return ret;
}



/***********************
 ***  Line Analysis  ***
 ***********************/

static int
md_is_hr_line(MD_CTX* ctx, OFF beg, OFF* p_end, OFF* p_killer)
{
    OFF off = beg + 1;
    int n = 1;

    while(off < ctx.size  &&  (ctx.CH(off) == ctx.CH(beg) || ctx.CH(off) == ' ' || ctx.CH(off) == '\t')) {
        if(ctx.CH(off) == ctx.CH(beg))
            n++;
        off++;
    }

    if(n < 3) {
        *p_killer = off;
        return FALSE;
    }

    /* Nothing else can be present on the line. */
    if(off < ctx.size  &&  !ctx.ISNEWLINE(off)) {
        *p_killer = off;
        return FALSE;
    }

    *p_end = off;
    return TRUE;
}

static int
md_is_atxheader_line(MD_CTX* ctx, OFF beg, OFF* p_beg, OFF* p_end, uint* p_level)
{
    int n;
    OFF off = beg + 1;

    while(off < ctx.size  &&  ctx.CH(off) == '#'  &&  off - beg < 7)
        off++;
    n = off - beg;

    if(n > 6)
        return FALSE;
    *p_level = n;

    if(!(ctx.parser.flags & MD_FLAG_PERMISSIVEATXHEADERS)  &&  off < ctx.size  &&
       ctx.CH(off) != ' '  &&  ctx.CH(off) != '\t'  &&  !ctx.ISNEWLINE(off))
        return FALSE;

    while(off < ctx.size  &&  ctx.CH(off) == ' ')
        off++;
    *p_beg = off;
    *p_end = off;
    return TRUE;
}

static int
md_is_setext_underline(MD_CTX* ctx, OFF beg, OFF* p_end, uint* p_level)
{
    OFF off = beg + 1;

    while(off < ctx.size  &&  ctx.CH(off) == ctx.CH(beg))
        off++;

    /* Optionally, space(s) can follow. */
    while(off < ctx.size  &&  ctx.CH(off) == ' ')
        off++;

    /* But nothing more is allowed on the line. */
    if(off < ctx.size  &&  !ctx.ISNEWLINE(off))
        return FALSE;

    *p_level = (ctx.CH(beg) == '=' ? 1 : 2);
    *p_end = off;
    return TRUE;
}

int md_is_table_underline(MD_CTX* ctx, OFF beg, OFF* p_end, uint* p_col_count)
{
    OFF off = beg;
    int found_pipe = FALSE;
    uint col_count = 0;

    if(off < ctx.size  &&  ctx.CH(off) == '|') {
        found_pipe = TRUE;
        off++;
        while(off < ctx.size  &&  ctx.ISWHITESPACE(off))
            off++;
    }

    while(1) {
        OFF cell_beg;
        int delimited = FALSE;

        /* Cell underline ("-----", ":----", "----:" or ":----:") */
        cell_beg = off;
        if(off < ctx.size  &&  ctx.CH(off) == ':')
            off++;
        while(off < ctx.size  &&  ctx.CH(off) == '-')
            off++;
        if(off < ctx.size  &&  ctx.CH(off) == ':')
            off++;
        if(off - cell_beg < 3)
            return FALSE;

        col_count++;

        /* Pipe delimiter (optional at the end of line). */
        while(off < ctx.size  &&  ctx.ISWHITESPACE(off))
            off++;
        if(off < ctx.size  &&  ctx.CH(off) == '|') {
            delimited = TRUE;
            found_pipe =  TRUE;
            off++;
            while(off < ctx.size  &&  ctx.ISWHITESPACE(off))
                off++;
        }

        /* Success, if we reach end of line. */
        if(off >= ctx.size  ||  ctx.ISNEWLINE(off))
            break;

        if(!delimited)
            return FALSE;
    }

    if(!found_pipe)
        return FALSE;

    *p_end = off;
    *p_col_count = col_count;
    return TRUE;
}

static int
md_is_opening_code_fence(MD_CTX* ctx, OFF beg, OFF* p_end)
{
    OFF off = beg;

    while(off < ctx.size && ctx.CH(off) == ctx.CH(beg))
        off++;

    /* Fence must have at least three characters. */
    if(off - beg < 3)
        return FALSE;

    ctx.code_fence_length = off - beg;

    /* Optionally, space(s) can follow. */
    while(off < ctx.size  &&  ctx.CH(off) == ' ')
        off++;

    /* Optionally, an info string can follow. */
    while(off < ctx.size  &&  !ctx.ISNEWLINE(off)) {
        /* Backtick-based fence must not contain '`' in the info string. */
        if(ctx.CH(beg) == '`'  &&  ctx.CH(off) == '`')
            return FALSE;
        off++;
    }

    *p_end = off;
    return TRUE;
}

static int
md_is_closing_code_fence(MD_CTX* ctx, CHAR ch, OFF beg, OFF* p_end)
{
    OFF off = beg;
    int ret = FALSE;

    /* Closing fence must have at least the same length and use same char as
     * opening one. */
    while(off < ctx.size  &&  ctx.CH(off) == ch)
        off++;
    if(off - beg < ctx.code_fence_length)
        goto out_;

    /* Optionally, space(s) can follow */
    while(off < ctx.size  &&  ctx.CH(off) == ' ')
        off++;

    /* But nothing more is allowed on the line. */
    if(off < ctx.size  &&  !ctx.ISNEWLINE(off))
        goto out_;

    ret = TRUE;

out_:
    /* Note we set *p_end even on failure: If we are not closing fence, caller
     * would eat the line anyway without any parsing. */
    *p_end = off;
    return ret;
}

/* Returns type of the raw HTML block, or FALSE if it is not HTML block.
 * (Refer to CommonMark specification for details about the types.)
 */
int md_is_html_block_start_condition(MD_CTX* ctx, OFF beg)
{
    /* Type 6 is started by a long list of allowed tags. We use two-level
     * tree to speed-up the search. */

    static immutable string Xend = null;
    static immutable string[] t1 = [ "script", "pre", "style", Xend ];
    static immutable string[] a6 = [ "address", "article", "aside", Xend ];
    static immutable string[] b6 = [ "base", "basefont", "blockquote", "body", Xend ];
    static immutable string[] c6 = [ "caption", "center", "col", "colgroup", Xend ];
    static immutable string[] d6 = [ "dd", "details", "dialog", "dir",
                                     "div", "dl", "dt", Xend ];
    static immutable string[] f6 = [ "fieldset", "figcaption", "figure", "footer",
                                     "form", "frame", "frameset", Xend ];
    static immutable string[] h6 = [ "h1", "head", "header", "hr", "html", Xend ];
    static immutable string[] i6 = [ "iframe", Xend ];
    static immutable string[] l6 = [ "legend", "li", "link", Xend ];
    static immutable string[] m6 = [ "main", "menu", "menuitem", Xend ];
    static immutable string[] n6 = [ "nav", "noframes", Xend ];
    static immutable string[] o6 = [ "ol", "optgroup", "option", Xend ];
    static immutable string[] p6 = [ "p", "param", Xend ];
    static immutable string[] s6 = [ "section", "source", "summary", Xend ];
    static immutable string[] t6 = [ "table", "tbody", "td", "tfoot", "th",
                                     "thead", "title", "tr", "track", Xend ];
    static immutable string[] u6 = [ "ul", Xend ];
    static immutable string[] xx = [ Xend ];

    immutable(string)*[26] map6;
    map6[0] = a6.ptr;
    map6[1] = b6.ptr;
    map6[2] = c6.ptr;
    map6[3] = d6.ptr;
    map6[4] = xx.ptr;
    map6[5] = f6.ptr;
    map6[6] = xx.ptr;
    map6[7] = h6.ptr;
    map6[8] = i6.ptr;
    map6[9] = xx.ptr;
    map6[10] = xx.ptr;
    map6[11] = l6.ptr;
    map6[12] = m6.ptr;
    map6[13] = n6.ptr;
    map6[14] = o6.ptr;
    map6[15] = p6.ptr;
    map6[16] = xx.ptr;
    map6[17] = xx.ptr;
    map6[18] = s6.ptr;
    map6[19] = t6.ptr;
    map6[20] = u6.ptr;
    map6[21] = xx.ptr;
    map6[22] = xx.ptr;
    map6[23] = xx.ptr;
    map6[24] = xx.ptr;
    map6[25] = xx.ptr;

    OFF off = beg + 1;
    int i;

    /* Check for type 1: <script, <pre, or <style */
    for(i = 0; t1[i].ptr != null; i++)
    {
        if(off + t1[i].length <= ctx.size)
        {
            if(md_ascii_case_eq(ctx.STR(off), t1[i].ptr, cast(uint)(t1[i].length)))
                return 1;
        }
    }

    /* Check for type 2: <!-- */
    if(off + 3 < ctx.size  &&  ctx.CH(off) == '!'  &&  ctx.CH(off+1) == '-'  &&  ctx.CH(off+2) == '-')
        return 2;

    /* Check for type 3: <? */
    if(off < ctx.size  &&  ctx.CH(off) == '?')
        return 3;

    /* Check for type 4 or 5: <! */
    if(off < ctx.size  &&  ctx.CH(off) == '!') {
        /* Check for type 4: <! followed by uppercase letter. */
        if(off + 1 < ctx.size  &&  ctx.ISUPPER(off+1))
            return 4;

        /* Check for type 5: <![CDATA[ */
        if(off + 8 < ctx.size) {
            if(md_ascii_eq(ctx.STR(off), "![CDATA[", 8 * CHAR.sizeof))
                return 5;
        }
    }

    /* Check for type 6: Many possible starting tags listed above. */
    if(off + 1 < ctx.size  &&  (ctx.ISALPHA(off) || (ctx.CH(off) == '/' && ctx.ISALPHA(off+1)))) {
        int slot;
        const(string)* tags;

        if(ctx.CH(off) == '/')
            off++;

        slot = (ctx.ISUPPER(off) ? ctx.CH(off) - 'A' : ctx.CH(off) - 'a');
        tags = map6[slot];

        for(i = 0; tags[i].ptr != null; i++) {
            if(off + tags[i].length <= ctx.size) {
                if(md_ascii_case_eq(ctx.STR(off), tags[i].ptr, cast(uint) tags[i].length)) {
                    OFF tmp = cast(uint)(off + tags[i].length);
                    if(tmp >= ctx.size)
                        return 6;
                    if(ctx.ISBLANK(tmp) || ctx.ISNEWLINE(tmp) || ctx.CH(tmp) == '>')
                        return 6;
                    if(tmp+1 < ctx.size && ctx.CH(tmp) == '/' && ctx.CH(tmp+1) == '>')
                        return 6;
                    break;
                }
            }
        }
    }

    /* Check for type 7: any COMPLETE other opening or closing tag. */
    if(off + 1 < ctx.size) {
        OFF end;

        if(md_is_html_tag(ctx, null, 0, beg, ctx.size, &end)) {
            /* Only optional whitespace and new line may follow. */
            while(end < ctx.size  &&  ctx.ISWHITESPACE(end))
                end++;
            if(end >= ctx.size  ||  ctx.ISNEWLINE(end))
                return 7;
        }
    }

    return FALSE;
}

/* Case sensitive check whether there is a substring 'what' between 'beg'
 * and end of line. */
static int
md_line_contains(MD_CTX* ctx, OFF beg, const(CHAR)* what, SZ what_len, OFF* p_end)
{
    OFF i;
    for(i = beg; i + what_len < ctx.size; i++) {
        if(ctx.ISNEWLINE(i))
            break;
        if(memcmp(ctx.STR(i), what, what_len * CHAR.sizeof) == 0) {
            *p_end = i + what_len;
            return TRUE;
        }
    }

    *p_end = i;
    return FALSE;
}

/* Returns type of HTML block end condition or FALSE if not an end condition.
 *
 * Note it fills p_end even when it is not end condition as the caller
 * does not need to analyze contents of a raw HTML block.
 */
int md_is_html_block_end_condition(MD_CTX* ctx, OFF beg, OFF* p_end)
{
    switch(ctx.html_block_type) {
        case 1:
        {
            OFF off = beg;

            while(off < ctx.size  &&  !ctx.ISNEWLINE(off)) {
                if(ctx.CH(off) == '<') {
                    if(md_ascii_case_eq(ctx.STR(off), "</script>", 9)) {
                        *p_end = off + 9;
                        return TRUE;
                    }

                    if(md_ascii_case_eq(ctx.STR(off), "</style>", 8)) {
                        *p_end = off + 8;
                        return TRUE;
                    }

                    if(md_ascii_case_eq(ctx.STR(off), "</pre>", 6)) {
                        *p_end = off + 6;
                        return TRUE;
                    }
                }

                off++;
            }
            *p_end = off;
            return FALSE;
        }

        case 2:
            return (md_line_contains(ctx, beg, "-->", 3, p_end) ? 2 : FALSE);

        case 3:
            return (md_line_contains(ctx, beg, "?>", 2, p_end) ? 3 : FALSE);

        case 4:
            return (md_line_contains(ctx, beg, ">", 1, p_end) ? 4 : FALSE);

        case 5:
            return (md_line_contains(ctx, beg, "]]>", 3, p_end) ? 5 : FALSE);

        case 6:     /* Pass through */
        case 7:
            *p_end = beg;
            return (ctx.ISNEWLINE(beg) ? ctx.html_block_type : FALSE);

        default:
            assert(false);
    }
}


static int
md_is_container_compatible(const MD_CONTAINER* pivot, const MD_CONTAINER* container)
{
    /* Block quote has no "items" like lists. */
    if(container.ch == '>')
        return FALSE;

    if(container.ch != pivot.ch)
        return FALSE;
    if(container.mark_indent > pivot.contents_indent)
        return FALSE;

    return TRUE;
}

static int
md_push_container(MD_CTX* ctx, const MD_CONTAINER* container)
{
    if(ctx.n_containers >= ctx.alloc_containers) {
        MD_CONTAINER* new_containers;

        ctx.alloc_containers = (ctx.alloc_containers > 0 ? ctx.alloc_containers * 2 : 16);
        new_containers = cast(MD_CONTAINER*) realloc_safe(ctx.containers, ctx.alloc_containers * MD_CONTAINER.sizeof);
        if (new_containers == null) {
            ctx.MD_LOG("realloc() failed.");
            return -1;
        }

        ctx.containers = new_containers;
    }

    memcpy(&ctx.containers[ctx.n_containers++], container, MD_CONTAINER.sizeof);
    return 0;
}

static int
md_enter_child_containers(MD_CTX* ctx, int n_children, uint data)
{
    int i;
    int ret = 0;

    for(i = ctx.n_containers - n_children; i < ctx.n_containers; i++) {
        MD_CONTAINER* c = &ctx.containers[i];
        int is_ordered_list = FALSE;

        switch(c.ch) {
            case ')':
            case '.':
                is_ordered_list = TRUE;
                /* Pass through */
                goto case '-';

            case '-':
            case '+':
            case '*':
                /* Remember offset in ctx.block_bytes so we can revisit the
                 * block if we detect it is a loose list. */
                md_end_current_block(ctx);
                c.block_byte_off = ctx.n_block_bytes;

                ret = (md_push_container_bytes(ctx,
                                (is_ordered_list ? MD_BLOCK_OL : MD_BLOCK_UL),
                                c.start, data, MD_BLOCK_CONTAINER_OPENER));
                if (ret < 0) goto abort;
                ret = (md_push_container_bytes(ctx, MD_BLOCK_LI,
                                c.task_mark_off,
                                (c.is_task ? ctx.CH(c.task_mark_off) : 0),
                                MD_BLOCK_CONTAINER_OPENER));
                if (ret < 0) goto abort;
                break;

            case '>':
                ret = (md_push_container_bytes(ctx, MD_BLOCK_QUOTE, 0, 0, MD_BLOCK_CONTAINER_OPENER));
                if (ret < 0) goto abort;
                break;

            default:
                assert(false);
        }
    }

abort:
    return ret;
}

static int
md_leave_child_containers(MD_CTX* ctx, int n_keep)
{
    int ret = 0;

    while(ctx.n_containers > n_keep) {
        MD_CONTAINER* c = &ctx.containers[ctx.n_containers-1];
        int is_ordered_list = FALSE;

        switch(c.ch) {
            case ')':
            case '.':
                is_ordered_list = TRUE;
                /* Pass through */
                goto case '-';

            case '-':
            case '+':
            case '*':
                ret = (md_push_container_bytes(ctx, MD_BLOCK_LI,
                                c.task_mark_off, (c.is_task ? ctx.CH(c.task_mark_off) : 0),
                                MD_BLOCK_CONTAINER_CLOSER));
                if (ret < 0) goto abort;
                ret = (md_push_container_bytes(ctx,
                                (is_ordered_list ? MD_BLOCK_OL : MD_BLOCK_UL), 0,
                                c.ch, MD_BLOCK_CONTAINER_CLOSER));
                if (ret < 0) goto abort;
                break;

            case '>':
                ret = (md_push_container_bytes(ctx, MD_BLOCK_QUOTE, 0,
                                0, MD_BLOCK_CONTAINER_CLOSER));
                if (ret < 0) goto abort;
                break;

            default:
                assert(false);
        }

        ctx.n_containers--;
    }

abort:
    return ret;
}

static int
md_is_container_mark(MD_CTX* ctx, uint indent, OFF beg, OFF* p_end, MD_CONTAINER* p_container)
{
    OFF off = beg;
    OFF max_end;

    if(indent >= ctx.code_indent_offset)
        return FALSE;

    /* Check for block quote mark. */
    if(off < ctx.size  &&  ctx.CH(off) == '>') {
        off++;
        p_container.ch = '>';
        p_container.is_loose = FALSE;
        p_container.is_task = FALSE;
        p_container.mark_indent = indent;
        p_container.contents_indent = indent + 1;
        *p_end = off;
        return TRUE;
    }

    /* Check for list item bullet mark. */
    if(off+1 < ctx.size  &&  ctx.ISANYOF(off, "-+*")  &&  (ctx.ISBLANK(off+1) || ctx.ISNEWLINE(off+1))) {
        p_container.ch = ctx.CH(off);
        p_container.is_loose = FALSE;
        p_container.is_task = FALSE;
        p_container.mark_indent = indent;
        p_container.contents_indent = indent + 1;
        *p_end = off + 1;
        return TRUE;
    }

    /* Check for ordered list item marks. */
    max_end = off + 9;
    if(max_end > ctx.size)
        max_end = ctx.size;
    p_container.start = 0;
    while(off < max_end  &&  ctx.ISDIGIT(off)) {
        p_container.start = p_container.start * 10 + ctx.CH(off) - '0';
        off++;
    }
    if(off+1 < ctx.size  &&  (ctx.CH(off) == '.' || ctx.CH(off) == ')')   &&  (ctx.ISBLANK(off+1) || ctx.ISNEWLINE(off+1))) {
        p_container.ch = ctx.CH(off);
        p_container.is_loose = FALSE;
        p_container.is_task = FALSE;
        p_container.mark_indent = indent;
        p_container.contents_indent = indent + off - beg + 1;
        *p_end = off + 1;
        return TRUE;
    }

    return FALSE;
}

uint md_line_indentation(MD_CTX* ctx, uint total_indent, OFF beg, OFF* p_end)
{
    OFF off = beg;
    uint indent = total_indent;

    while(off < ctx.size  &&  ctx.ISBLANK(off)) {
        if(ctx.CH(off) == '\t')
            indent = (indent + 4) & ~3;
        else
            indent++;
        off++;
    }

    *p_end = off;
    return indent - total_indent;
}

static const MD_LINE_ANALYSIS md_dummy_blank_line = { MD_LINE_BLANK, 0 };

/* Analyze type of the line and find some its properties. This serves as a
 * main input for determining type and boundaries of a block. */
int md_analyze_line(MD_CTX* ctx, OFF beg, OFF* p_end,
                    const(MD_LINE_ANALYSIS)* pivot_line, MD_LINE_ANALYSIS* line)
{
    uint total_indent = 0;
    int n_parents = 0;
    int n_brothers = 0;
    int n_children = 0;
    MD_CONTAINER container = { 0 };
    int prev_line_has_list_loosening_effect = ctx.last_line_has_list_loosening_effect;
    OFF off = beg;
    OFF hr_killer = 0;
    int ret = 0;

    line.indent = md_line_indentation(ctx, total_indent, off, &off);
    total_indent += line.indent;
    line.beg = off;

    /* Given the indentation and block quote marks '>', determine how many of
     * the current containers are our parents. */
    while(n_parents < ctx.n_containers) {
        MD_CONTAINER* c = &ctx.containers[n_parents];

        if(c.ch == '>'  &&  line.indent < ctx.code_indent_offset  &&
            off < ctx.size  &&  ctx.CH(off) == '>')
        {
            /* Block quote mark. */
            off++;
            total_indent++;
            line.indent = md_line_indentation(ctx, total_indent, off, &off);
            total_indent += line.indent;

            /* The optional 1st space after '>' is part of the block quote mark. */
            if(line.indent > 0)
                line.indent--;

            line.beg = off;
        } else if(c.ch != '>'  &&  line.indent >= c.contents_indent) {
            /* List. */
            line.indent -= c.contents_indent;
        } else {
            break;
        }

        n_parents++;
    }

    if(off >= ctx.size  ||  ctx.ISNEWLINE(off)) {
        /* Blank line does not need any real indentation to be nested inside
         * a list. */
        if(n_brothers + n_children == 0) {
            while(n_parents < ctx.n_containers  &&  ctx.containers[n_parents].ch != '>')
                n_parents++;
        }
    }

    while(TRUE) {
        /* Check whether we are fenced code continuation. */
        if(pivot_line.type == MD_LINE_FENCEDCODE) {
            line.beg = off;

            /* We are another MD_LINE_FENCEDCODE unless we are closing fence
             * which we transform into MD_LINE_BLANK. */
            if(line.indent < ctx.code_indent_offset) {
                if(md_is_closing_code_fence(ctx, ctx.CH(pivot_line.beg), off, &off)) {
                    line.type = MD_LINE_BLANK;
                    ctx.last_line_has_list_loosening_effect = FALSE;
                    break;
                }
            }

            /* Change indentation accordingly to the initial code fence. */
            if(n_parents == ctx.n_containers) {
                if(line.indent > pivot_line.indent)
                    line.indent -= pivot_line.indent;
                else
                    line.indent = 0;

                line.type = MD_LINE_FENCEDCODE;
                break;
            }
        }

        /* Check whether we are HTML block continuation. */
        if(pivot_line.type == MD_LINE_HTML  &&  ctx.html_block_type > 0) {
            int html_block_type;

            html_block_type = md_is_html_block_end_condition(ctx, off, &off);
            if(html_block_type > 0) {
                assert(html_block_type == ctx.html_block_type);

                /* Make sure this is the last line of the block. */
                ctx.html_block_type = 0;

                /* Some end conditions serve as blank lines at the same time. */
                if(html_block_type == 6 || html_block_type == 7) {
                    line.type = MD_LINE_BLANK;
                    line.indent = 0;
                    break;
                }
            }

            if(n_parents == ctx.n_containers) {
                line.type = MD_LINE_HTML;
                break;
            }
        }

        /* Check for blank line. */
        if(off >= ctx.size  ||  ctx.ISNEWLINE(off)) {
            if(pivot_line.type == MD_LINE_INDENTEDCODE  &&  n_parents == ctx.n_containers) {
                line.type = MD_LINE_INDENTEDCODE;
                if(line.indent > ctx.code_indent_offset)
                    line.indent -= ctx.code_indent_offset;
                else
                    line.indent = 0;
                ctx.last_line_has_list_loosening_effect = FALSE;
            } else {
                line.type = MD_LINE_BLANK;
                ctx.last_line_has_list_loosening_effect = (n_parents > 0  &&
                        n_brothers + n_children == 0  &&
                        ctx.containers[n_parents-1].ch != '>');

                /* See https://github.com/mity/md4c/issues/6
                 *
                 * This ugly checking tests we are in (yet empty) list item but not
                 * its very first line (with the list item mark).
                 *
                 * If we are such blank line, then any following non-blank line
                 * which would be part of this list item actually ends the list
                 * because "a list item can begin with at most one blank line."
                 */
                if(n_parents > 0  &&  ctx.containers[n_parents-1].ch != '>'  &&
                   n_brothers + n_children == 0  &&  ctx.current_block == null  &&
                   ctx.n_block_bytes > cast(int) MD_BLOCK.sizeof)
                {
                    MD_BLOCK* top_block = cast(MD_BLOCK*) (cast(char*)ctx.block_bytes + ctx.n_block_bytes - MD_BLOCK.sizeof);
                    if(top_block.type == MD_BLOCK_LI)
                        ctx.last_list_item_starts_with_two_blank_lines = TRUE;
                }
                }
            break;
        } else {
            /* This is 2nd half of the hack. If the flag is set (that is there
             * were 2nd blank line at the start of the list item) and we would also
             * belonging to such list item, then interrupt the list. */
            ctx.last_line_has_list_loosening_effect = FALSE;
            if(ctx.last_list_item_starts_with_two_blank_lines) {
                if(n_parents > 0  &&  ctx.containers[n_parents-1].ch != '>'  &&
                   n_brothers + n_children == 0  &&  ctx.current_block == null  &&
                   ctx.n_block_bytes > cast(int) MD_BLOCK.sizeof)
                {
                    MD_BLOCK* top_block = cast(MD_BLOCK*) (cast(char*)ctx.block_bytes + ctx.n_block_bytes - MD_BLOCK.sizeof);
                    if(top_block.type == MD_BLOCK_LI)
                        n_parents--;
                }

                ctx.last_list_item_starts_with_two_blank_lines = FALSE;
            }
        }

        /* Check whether we are Setext underline. */
        if(line.indent < ctx.code_indent_offset  &&  pivot_line.type == MD_LINE_TEXT
            &&  (ctx.CH(off) == '=' || ctx.CH(off) == '-')
            &&  (n_parents == ctx.n_containers))
        {
            uint level;

            if(md_is_setext_underline(ctx, off, &off, &level)) {
                line.type = MD_LINE_SETEXTUNDERLINE;
                line.data = level;
                break;
            }
        }

        /* Check for thematic break line. */
        if(line.indent < ctx.code_indent_offset  &&  ctx.ISANYOF(off, "-_*")  &&  off >= hr_killer) {
            if(md_is_hr_line(ctx, off, &off, &hr_killer)) {
                line.type = MD_LINE_HR;
                break;
            }
        }

        /* Check for "brother" container. I.e. whether we are another list item
         * in already started list. */
        if(n_parents < ctx.n_containers  &&  n_brothers + n_children == 0) {
            OFF tmp;

            if(md_is_container_mark(ctx, line.indent, off, &tmp, &container)  &&
               md_is_container_compatible(&ctx.containers[n_parents], &container))
            {
                pivot_line = &md_dummy_blank_line;

                off = tmp;

                total_indent += container.contents_indent - container.mark_indent;
                line.indent = md_line_indentation(ctx, total_indent, off, &off);
                total_indent += line.indent;
                line.beg = off;

                /* Some of the following whitespace actually still belongs to the mark. */
                if(off >= ctx.size || ctx.ISNEWLINE(off)) {
                    container.contents_indent++;
                } else if(line.indent <= ctx.code_indent_offset) {
                    container.contents_indent += line.indent;
                    line.indent = 0;
                } else {
                    container.contents_indent += 1;
                    line.indent--;
                }

                ctx.containers[n_parents].mark_indent = container.mark_indent;
                ctx.containers[n_parents].contents_indent = container.contents_indent;

                n_brothers++;
                continue;
            }
        }

        /* Check for indented code.
         * Note indented code block cannot interrupt a paragraph. */
        if(line.indent >= ctx.code_indent_offset  &&
            (pivot_line.type == MD_LINE_BLANK || pivot_line.type == MD_LINE_INDENTEDCODE))
        {
            line.type = MD_LINE_INDENTEDCODE;
            assert(line.indent >= ctx.code_indent_offset);
            line.indent -= ctx.code_indent_offset;
            line.data = 0;
            break;
        }

        /* Check for start of a new container block. */
        if(line.indent < ctx.code_indent_offset  &&
           md_is_container_mark(ctx, line.indent, off, &off, &container))
        {
            if(pivot_line.type == MD_LINE_TEXT  &&  n_parents == ctx.n_containers  &&
                        (off >= ctx.size || ctx.ISNEWLINE(off))  &&  container.ch != '>')
            {
                /* Noop. List mark followed by a blank line cannot interrupt a paragraph. */
            } else if(pivot_line.type == MD_LINE_TEXT  &&  n_parents == ctx.n_containers  &&
                        (container.ch == '.' || container.ch == ')')  &&  container.start != 1)
            {
                /* Noop. Ordered list cannot interrupt a paragraph unless the start index is 1. */
            } else {
                total_indent += container.contents_indent - container.mark_indent;
                line.indent = md_line_indentation(ctx, total_indent, off, &off);
                total_indent += line.indent;

                line.beg = off;
                line.data = container.ch;

                /* Some of the following whitespace actually still belongs to the mark. */
                if(off >= ctx.size || ctx.ISNEWLINE(off)) {
                    container.contents_indent++;
                } else if(line.indent <= ctx.code_indent_offset) {
                    container.contents_indent += line.indent;
                    line.indent = 0;
                } else {
                    container.contents_indent += 1;
                    line.indent--;
                }

                if(n_brothers + n_children == 0)
                    pivot_line = &md_dummy_blank_line;

                if(n_children == 0)
                {
                    ret = (md_leave_child_containers(ctx, n_parents + n_brothers));
                    if (ret < 0) goto abort;
                }

                n_children++;
                ret = (md_push_container(ctx, &container));
                if (ret < 0) goto abort;
                continue;
            }
        }

        /* Check whether we are table continuation. */
        if(pivot_line.type == MD_LINE_TABLE  &&  md_is_table_row(ctx, off, &off)  &&
           n_parents == ctx.n_containers)
        {
            line.type = MD_LINE_TABLE;
            break;
        }

        /* Check for ATX header. */
        if(line.indent < ctx.code_indent_offset  &&  ctx.CH(off) == '#') {
            uint level;

            if(md_is_atxheader_line(ctx, off, &line.beg, &off, &level)) {
                line.type = MD_LINE_ATXHEADER;
                line.data = level;
                break;
            }
        }

        /* Check whether we are starting code fence. */
        if(ctx.CH(off) == '`' || ctx.CH(off) == '~') {
            if(md_is_opening_code_fence(ctx, off, &off)) {
                line.type = MD_LINE_FENCEDCODE;
                line.data = 1;
                break;
            }
        }

        /* Check for start of raw HTML block. */
        if(ctx.CH(off) == '<'  &&  !(ctx.parser.flags & MD_FLAG_NOHTMLBLOCKS))
        {
            ctx.html_block_type = md_is_html_block_start_condition(ctx, off);

            /* HTML block type 7 cannot interrupt paragraph. */
            if(ctx.html_block_type == 7  &&  pivot_line.type == MD_LINE_TEXT)
                ctx.html_block_type = 0;

            if(ctx.html_block_type > 0) {
                /* The line itself also may immediately close the block. */
                if(md_is_html_block_end_condition(ctx, off, &off) == ctx.html_block_type) {
                    /* Make sure this is the last line of the block. */
                    ctx.html_block_type = 0;
                }

                line.type = MD_LINE_HTML;
                break;
            }
        }

        /* Check for table underline. */
        if((ctx.parser.flags & MD_FLAG_TABLES)  &&  pivot_line.type == MD_LINE_TEXT  &&
           (ctx.CH(off) == '|' || ctx.CH(off) == '-' || ctx.CH(off) == ':')  &&
           n_parents == ctx.n_containers)
        {
            uint col_count;

            if(ctx.current_block != null  &&  ctx.current_block.n_lines == 1  &&
                md_is_table_underline(ctx, off, &off, &col_count)  &&
                md_is_table_row(ctx, pivot_line.beg, null))
            {
                line.data = col_count;
                line.type = MD_LINE_TABLEUNDERLINE;
                break;
            }
        }

        /* By default, we are normal text line. */
        line.type = MD_LINE_TEXT;
        if(pivot_line.type == MD_LINE_TEXT  &&  n_brothers + n_children == 0) {
            /* Lazy continuation. */
            n_parents = ctx.n_containers;
        }

        /* Check for task mark. */
        if((ctx.parser.flags & MD_FLAG_TASKLISTS)  &&  n_brothers + n_children > 0  &&
           ISANYOF_(ctx.containers[ctx.n_containers-1].ch, "-+*.)"))
        {
            OFF tmp = off;

            while(tmp < ctx.size  &&  tmp < off + 3  &&  ctx.ISBLANK(tmp))
                tmp++;
            if(tmp + 2 < ctx.size  &&  ctx.CH(tmp) == '['  &&
               ctx.ISANYOF(tmp+1, "xX ")  &&  ctx.CH(tmp+2) == ']'  &&
               (tmp + 3 == ctx.size  ||  ctx.ISBLANK(tmp+3)  ||  ctx.ISNEWLINE(tmp+3)))
            {
                MD_CONTAINER* task_container = (n_children > 0 ? &ctx.containers[ctx.n_containers-1] : &container);
                task_container.is_task = TRUE;
                task_container.task_mark_off = tmp + 1;
                off = tmp + 3;
                while(ctx.ISWHITESPACE(off))
                    off++;
                line.beg = off;
            }
        }

        break;
    }

    /* Scan for end of the line.
     *
     * Note this is quite a bottleneck of the parsing as we here iterate almost
     * over compete document.
     */
    {
        /* Optimization: Use some loop unrolling. */
        while(off + 3 < ctx.size  &&  !ctx.ISNEWLINE(off+0)  &&  !ctx.ISNEWLINE(off+1)
                                   &&  !ctx.ISNEWLINE(off+2)  &&  !ctx.ISNEWLINE(off+3))
            off += 4;
        while(off < ctx.size  &&  !ctx.ISNEWLINE(off))
            off++;
    }

    /* Set end of the line. */
    line.end = off;

    /* But for ATX header, we should exclude the optional trailing mark. */
    if(line.type == MD_LINE_ATXHEADER) {
        OFF tmp = line.end;
        while(tmp > line.beg && ctx.CH(tmp-1) == ' ')
            tmp--;
        while(tmp > line.beg && ctx.CH(tmp-1) == '#')
            tmp--;
        if(tmp == line.beg || ctx.CH(tmp-1) == ' ' || (ctx.parser.flags & MD_FLAG_PERMISSIVEATXHEADERS))
            line.end = tmp;
    }

    /* Trim trailing spaces. */
    if(line.type != MD_LINE_INDENTEDCODE  &&  line.type != MD_LINE_FENCEDCODE) {
        while(line.end > line.beg && ctx.CH(line.end-1) == ' ')
            line.end--;
    }

    /* Eat also the new line. */
    if(off < ctx.size && ctx.CH(off) == '\r')
        off++;
    if(off < ctx.size && ctx.CH(off) == '\n')
        off++;

    *p_end = off;

    /* If we belong to a list after seeing a blank line, the list is loose. */
    if(prev_line_has_list_loosening_effect  &&  line.type != MD_LINE_BLANK  &&  n_parents + n_brothers > 0) {
        MD_CONTAINER* c = &ctx.containers[n_parents + n_brothers - 1];
        if(c.ch != '>') {
            MD_BLOCK* block = cast(MD_BLOCK*) ((cast(char*)ctx.block_bytes) + c.block_byte_off);
            block.flags = block.flags | MD_BLOCK_LOOSE_LIST;
        }
    }

    /* Leave any containers we are not part of anymore. */
    if(n_children == 0  &&  n_parents + n_brothers < ctx.n_containers)
    {
        ret = (md_leave_child_containers(ctx, n_parents + n_brothers));
        if (ret < 0) goto abort;
    }

    /* Enter any container we found a mark for. */
    if(n_brothers > 0) {
        assert(n_brothers == 1);
        ret = (md_push_container_bytes(ctx, MD_BLOCK_LI,
                    ctx.containers[n_parents].task_mark_off,
                    (ctx.containers[n_parents].is_task ? ctx.CH(ctx.containers[n_parents].task_mark_off) : 0),
                    MD_BLOCK_CONTAINER_CLOSER));
        if (ret < 0) goto abort;
        ret = (md_push_container_bytes(ctx, MD_BLOCK_LI,
                    container.task_mark_off,
                    (container.is_task ? ctx.CH(container.task_mark_off) : 0),
                    MD_BLOCK_CONTAINER_OPENER));
        if (ret < 0) goto abort;
        ctx.containers[n_parents].is_task = container.is_task;
        ctx.containers[n_parents].task_mark_off = container.task_mark_off;
    }

    if(n_children > 0)
    {
        ret = (md_enter_child_containers(ctx, n_children, line.data));
        if (ret < 0) goto abort;
    }

abort:
    return ret;
}

int md_process_line(MD_CTX* ctx, const(MD_LINE_ANALYSIS)** p_pivot_line, MD_LINE_ANALYSIS* line)
{
    const(MD_LINE_ANALYSIS)* pivot_line = *p_pivot_line;
    int ret = 0;

    /* Blank line ends current leaf block. */
    if(line.type == MD_LINE_BLANK) {
        ret = (md_end_current_block(ctx));
        if (ret < 0) goto abort;
        *p_pivot_line = &md_dummy_blank_line;
        return 0;
    }

    /* Some line types form block on their own. */
    if(line.type == MD_LINE_HR || line.type == MD_LINE_ATXHEADER) {
        ret = (md_end_current_block(ctx));
        if (ret < 0) goto abort;

        /* Add our single-line block. */
        ret = (md_start_new_block(ctx, line));
        if (ret < 0) goto abort;
        ret = (md_add_line_into_current_block(ctx, line));
        if (ret < 0) goto abort;
        ret = (md_end_current_block(ctx));
        if (ret < 0) goto abort;
        *p_pivot_line = &md_dummy_blank_line;
        return 0;
    }

    /* MD_LINE_SETEXTUNDERLINE changes meaning of the current block and ends it. */
    if(line.type == MD_LINE_SETEXTUNDERLINE) {
        assert(ctx.current_block != null);
        ctx.current_block.type = MD_BLOCK_H;
        ctx.current_block.data = line.data;
        ctx.current_block.flags = ctx.current_block.flags | MD_BLOCK_SETEXT_HEADER;
        ret = (md_add_line_into_current_block(ctx, line));
        if (ret < 0) goto abort;
        ret = (md_end_current_block(ctx));
        if (ret < 0) goto abort;
        if(ctx.current_block == null) {
            *p_pivot_line = &md_dummy_blank_line;
        } else {
            /* This happens if we have consumed all the body as link ref. defs.
             * and downgraded the underline into start of a new paragraph block. */
            line.type = MD_LINE_TEXT;
            *p_pivot_line = line;
        }
        return 0;
    }

    /* MD_LINE_TABLEUNDERLINE changes meaning of the current block. */
    if(line.type == MD_LINE_TABLEUNDERLINE) {
        assert(ctx.current_block != null);
        assert(ctx.current_block.n_lines == 1);
        ctx.current_block.type = MD_BLOCK_TABLE;
        ctx.current_block.data = line.data;
        assert(pivot_line != &md_dummy_blank_line);
        (cast(MD_LINE_ANALYSIS*)pivot_line).type = MD_LINE_TABLE;
        ret = (md_add_line_into_current_block(ctx, line));
        if (ret < 0) goto abort;
        return 0;
    }

    /* The current block also ends if the line has different type. */
    if(line.type != pivot_line.type)
    {
        ret = (md_end_current_block(ctx));
        if (ret < 0) goto abort;
    }

    /* The current line may start a new block. */
    if(ctx.current_block == null) {
        ret = (md_start_new_block(ctx, line));
        if (ret < 0) goto abort;
        *p_pivot_line = line;
    }

    /* In all other cases the line is just a continuation of the current block. */
    ret = (md_add_line_into_current_block(ctx, line));
    if (ret < 0) goto abort;

abort:
    return ret;
}

int md_process_doc(MD_CTX *ctx)
{
    const(MD_LINE_ANALYSIS)* pivot_line = &md_dummy_blank_line;
    MD_LINE_ANALYSIS[2] line_buf;
    MD_LINE_ANALYSIS* line = &line_buf[0];
    OFF off = 0;
    int ret = 0;

    ret = MD_ENTER_BLOCK(ctx, MD_BLOCK_DOC, null);
    if (ret != 0) goto abort;

    while(off < ctx.size) {
        if(line == pivot_line)
            line = (line == &line_buf[0] ? &line_buf[1] : &line_buf[0]);

        ret = (md_analyze_line(ctx, off, &off, pivot_line, line));
        if (ret < 0) goto abort;
        ret = (md_process_line(ctx, &pivot_line, line));
        if (ret < 0) goto abort;
    }

    md_end_current_block(ctx);

    ret = (md_build_ref_def_hashtable(ctx));
    if (ret < 0) goto abort;

    /* Process all blocks. */
    ret = (md_leave_child_containers(ctx, 0));
    if (ret < 0) goto abort;
    ret = (md_process_all_blocks(ctx));
    if (ret < 0) goto abort;

    ret = MD_LEAVE_BLOCK(ctx, MD_BLOCK_DOC, null);
    if (ret != 0) goto abort;

abort:

    debug(bench)
    /* Output some memory consumption statistics. */
    {
        char[256] buffer;
        sprintf(buffer, "Alloced %u bytes for block buffer.",
                    cast(uint)(ctx.alloc_block_bytes));
        ctx.MD_LOG(buffer);

        sprintf(buffer, "Alloced %u bytes for containers buffer.",
                    cast(uint)(ctx.alloc_containers * MD_CONTAINER.sizeof));
        ctx.MD_LOG(buffer);

        sprintf(buffer, "Alloced %u bytes for marks buffer.",
                    cast(uint)(ctx.alloc_marks * MD_MARK.sizeof));
        ctx.MD_LOG(buffer);

        sprintf(buffer, "Alloced %u bytes for aux. buffer.",
                    cast(uint)(ctx.alloc_buffer * MD_CHAR.sizeof));
        ctx.MD_LOG(buffer);
    }

    return ret;
}


/********************
 ***  Public API  ***
 ********************/

/**
 * Parse the Markdown document stored in the string 'text' of size 'size'.
 * The renderer provides callbacks to be called during the parsing so the
 * caller can render the document on the screen or convert the Markdown
 * to another format.
 *
 * Zero is returned on success. If a runtime error occurs (e.g. a memory
 * fails), -1 is returned. If the processing is aborted due any callback
 * returning non-zero, md_parse() the return value of the callback is returned.
 */
int md_parse(const MD_CHAR* text, MD_SIZE size, const MD_PARSER* parser, void* userdata)
{
    MD_CTX ctx;
    int i;
    int ret;

    if(parser.abi_version != 0) {
        if(parser.debug_log != null)
            parser.debug_log("Unsupported abi_version.", userdata);
        return -1;
    }

    /* Setup context structure. */
    memset(&ctx, 0, MD_CTX.sizeof);
    ctx.text = text;
    ctx.size = size;
    memcpy(&ctx.parser, parser, MD_PARSER.sizeof);
    ctx.userdata = userdata;
    ctx.code_indent_offset = (ctx.parser.flags & MD_FLAG_NOINDENTEDCODEBLOCKS) ? cast(OFF)(-1) : 4;
    md_build_mark_char_map(&ctx);
    ctx.doc_ends_with_newline = (size > 0  &&  ISNEWLINE_(text[size-1]));

    /* Reset all unresolved opener mark chains. */
    for(i = 0; i < cast(int) (ctx.mark_chains.length); i++) {
        ctx.mark_chains[i].head = -1;
        ctx.mark_chains[i].tail = -1;
    }
    ctx.unresolved_link_head = -1;
    ctx.unresolved_link_tail = -1;

    /* All the work. */
    ret = md_process_doc(&ctx);

    /* Clean-up. */
    md_free_ref_defs(&ctx);
    md_free_ref_def_hashtable(&ctx);
    free(ctx.buffer);
    free(ctx.marks);
    free(ctx.block_bytes);
    free(ctx.containers);

    return ret;
}

//
// HTML ENTITIES
//

/* Most entities are formed by single Unicode codepoint, few by two codepoints.
 * Single-codepoint entities have codepoints[1] set to zero. */
struct entity
{
    const(char)* name;
    uint[2] codepoints;
}

/* The table is generated from https://html.spec.whatwg.org/entities.json */
static immutable entity[] entity_table =
[
    entity( "&AElig;", [ 198, 0 ] ),
    entity( "&AMP;", [ 38, 0 ] ),
    entity( "&Aacute;", [ 193, 0 ] ),
    entity( "&Abreve;", [ 258, 0 ] ),
    entity( "&Acirc;", [ 194, 0 ] ),
    entity( "&Acy;", [ 1040, 0 ] ),
    entity( "&Afr;", [ 120068, 0 ] ),
    entity( "&Agrave;", [ 192, 0 ] ),
    entity( "&Alpha;", [ 913, 0 ] ),
    entity( "&Amacr;", [ 256, 0 ] ),
    entity( "&And;", [ 10835, 0 ] ),
    entity( "&Aogon;", [ 260, 0 ] ),
    entity( "&Aopf;", [ 120120, 0 ] ),
    entity( "&ApplyFunction;", [ 8289, 0 ] ),
    entity( "&Aring;", [ 197, 0 ] ),
    entity( "&Ascr;", [ 119964, 0 ] ),
    entity( "&Assign;", [ 8788, 0 ] ),
    entity( "&Atilde;", [ 195, 0 ] ),
    entity( "&Auml;", [ 196, 0 ] ),
    entity( "&Backslash;", [ 8726, 0 ] ),
    entity( "&Barv;", [ 10983, 0 ] ),
    entity( "&Barwed;", [ 8966, 0 ] ),
    entity( "&Bcy;", [ 1041, 0 ] ),
    entity( "&Because;", [ 8757, 0 ] ),
    entity( "&Bernoullis;", [ 8492, 0 ] ),
    entity( "&Beta;", [ 914, 0 ] ),
    entity( "&Bfr;", [ 120069, 0 ] ),
    entity( "&Bopf;", [ 120121, 0 ] ),
    entity( "&Breve;", [ 728, 0 ] ),
    entity( "&Bscr;", [ 8492, 0 ] ),
    entity( "&Bumpeq;", [ 8782, 0 ] ),
    entity( "&CHcy;", [ 1063, 0 ] ),
    entity( "&COPY;", [ 169, 0 ] ),
    entity( "&Cacute;", [ 262, 0 ] ),
    entity( "&Cap;", [ 8914, 0 ] ),
    entity( "&CapitalDifferentialD;", [ 8517, 0 ] ),
    entity( "&Cayleys;", [ 8493, 0 ] ),
    entity( "&Ccaron;", [ 268, 0 ] ),
    entity( "&Ccedil;", [ 199, 0 ] ),
    entity( "&Ccirc;", [ 264, 0 ] ),
    entity( "&Cconint;", [ 8752, 0 ] ),
    entity( "&Cdot;", [ 266, 0 ] ),
    entity( "&Cedilla;", [ 184, 0 ] ),
    entity( "&CenterDot;", [ 183, 0 ] ),
    entity( "&Cfr;", [ 8493, 0 ] ),
    entity( "&Chi;", [ 935, 0 ] ),
    entity( "&CircleDot;", [ 8857, 0 ] ),
    entity( "&CircleMinus;", [ 8854, 0 ] ),
    entity( "&CirclePlus;", [ 8853, 0 ] ),
    entity( "&CircleTimes;", [ 8855, 0 ] ),
    entity( "&ClockwiseContourIntegral;", [ 8754, 0 ] ),
    entity( "&CloseCurlyDoubleQuote;", [ 8221, 0 ] ),
    entity( "&CloseCurlyQuote;", [ 8217, 0 ] ),
    entity( "&Colon;", [ 8759, 0 ] ),
    entity( "&Colone;", [ 10868, 0 ] ),
    entity( "&Congruent;", [ 8801, 0 ] ),
    entity( "&Conint;", [ 8751, 0 ] ),
    entity( "&ContourIntegral;", [ 8750, 0 ] ),
    entity( "&Copf;", [ 8450, 0 ] ),
    entity( "&Coproduct;", [ 8720, 0 ] ),
    entity( "&CounterClockwiseContourIntegral;", [ 8755, 0 ] ),
    entity( "&Cross;", [ 10799, 0 ] ),
    entity( "&Cscr;", [ 119966, 0 ] ),
    entity( "&Cup;", [ 8915, 0 ] ),
    entity( "&CupCap;", [ 8781, 0 ] ),
    entity( "&DD;", [ 8517, 0 ] ),
    entity( "&DDotrahd;", [ 10513, 0 ] ),
    entity( "&DJcy;", [ 1026, 0 ] ),
    entity( "&DScy;", [ 1029, 0 ] ),
    entity( "&DZcy;", [ 1039, 0 ] ),
    entity( "&Dagger;", [ 8225, 0 ] ),
    entity( "&Darr;", [ 8609, 0 ] ),
    entity( "&Dashv;", [ 10980, 0 ] ),
    entity( "&Dcaron;", [ 270, 0 ] ),
    entity( "&Dcy;", [ 1044, 0 ] ),
    entity( "&Del;", [ 8711, 0 ] ),
    entity( "&Delta;", [ 916, 0 ] ),
    entity( "&Dfr;", [ 120071, 0 ] ),
    entity( "&DiacriticalAcute;", [ 180, 0 ] ),
    entity( "&DiacriticalDot;", [ 729, 0 ] ),
    entity( "&DiacriticalDoubleAcute;", [ 733, 0 ] ),
    entity( "&DiacriticalGrave;", [ 96, 0 ] ),
    entity( "&DiacriticalTilde;", [ 732, 0 ] ),
    entity( "&Diamond;", [ 8900, 0 ] ),
    entity( "&DifferentialD;", [ 8518, 0 ] ),
    entity( "&Dopf;", [ 120123, 0 ] ),
    entity( "&Dot;", [ 168, 0 ] ),
    entity( "&DotDot;", [ 8412, 0 ] ),
    entity( "&DotEqual;", [ 8784, 0 ] ),
    entity( "&DoubleContourIntegral;", [ 8751, 0 ] ),
    entity( "&DoubleDot;", [ 168, 0 ] ),
    entity( "&DoubleDownArrow;", [ 8659, 0 ] ),
    entity( "&DoubleLeftArrow;", [ 8656, 0 ] ),
    entity( "&DoubleLeftRightArrow;", [ 8660, 0 ] ),
    entity( "&DoubleLeftTee;", [ 10980, 0 ] ),
    entity( "&DoubleLongLeftArrow;", [ 10232, 0 ] ),
    entity( "&DoubleLongLeftRightArrow;", [ 10234, 0 ] ),
    entity( "&DoubleLongRightArrow;", [ 10233, 0 ] ),
    entity( "&DoubleRightArrow;", [ 8658, 0 ] ),
    entity( "&DoubleRightTee;", [ 8872, 0 ] ),
    entity( "&DoubleUpArrow;", [ 8657, 0 ] ),
    entity( "&DoubleUpDownArrow;", [ 8661, 0 ] ),
    entity( "&DoubleVerticalBar;", [ 8741, 0 ] ),
    entity( "&DownArrow;", [ 8595, 0 ] ),
    entity( "&DownArrowBar;", [ 10515, 0 ] ),
    entity( "&DownArrowUpArrow;", [ 8693, 0 ] ),
    entity( "&DownBreve;", [ 785, 0 ] ),
    entity( "&DownLeftRightVector;", [ 10576, 0 ] ),
    entity( "&DownLeftTeeVector;", [ 10590, 0 ] ),
    entity( "&DownLeftVector;", [ 8637, 0 ] ),
    entity( "&DownLeftVectorBar;", [ 10582, 0 ] ),
    entity( "&DownRightTeeVector;", [ 10591, 0 ] ),
    entity( "&DownRightVector;", [ 8641, 0 ] ),
    entity( "&DownRightVectorBar;", [ 10583, 0 ] ),
    entity( "&DownTee;", [ 8868, 0 ] ),
    entity( "&DownTeeArrow;", [ 8615, 0 ] ),
    entity( "&Downarrow;", [ 8659, 0 ] ),
    entity( "&Dscr;", [ 119967, 0 ] ),
    entity( "&Dstrok;", [ 272, 0 ] ),
    entity( "&ENG;", [ 330, 0 ] ),
    entity( "&ETH;", [ 208, 0 ] ),
    entity( "&Eacute;", [ 201, 0 ] ),
    entity( "&Ecaron;", [ 282, 0 ] ),
    entity( "&Ecirc;", [ 202, 0 ] ),
    entity( "&Ecy;", [ 1069, 0 ] ),
    entity( "&Edot;", [ 278, 0 ] ),
    entity( "&Efr;", [ 120072, 0 ] ),
    entity( "&Egrave;", [ 200, 0 ] ),
    entity( "&Element;", [ 8712, 0 ] ),
    entity( "&Emacr;", [ 274, 0 ] ),
    entity( "&EmptySmallSquare;", [ 9723, 0 ] ),
    entity( "&EmptyVerySmallSquare;", [ 9643, 0 ] ),
    entity( "&Eogon;", [ 280, 0 ] ),
    entity( "&Eopf;", [ 120124, 0 ] ),
    entity( "&Epsilon;", [ 917, 0 ] ),
    entity( "&Equal;", [ 10869, 0 ] ),
    entity( "&EqualTilde;", [ 8770, 0 ] ),
    entity( "&Equilibrium;", [ 8652, 0 ] ),
    entity( "&Escr;", [ 8496, 0 ] ),
    entity( "&Esim;", [ 10867, 0 ] ),
    entity( "&Eta;", [ 919, 0 ] ),
    entity( "&Euml;", [ 203, 0 ] ),
    entity( "&Exists;", [ 8707, 0 ] ),
    entity( "&ExponentialE;", [ 8519, 0 ] ),
    entity( "&Fcy;", [ 1060, 0 ] ),
    entity( "&Ffr;", [ 120073, 0 ] ),
    entity( "&FilledSmallSquare;", [ 9724, 0 ] ),
    entity( "&FilledVerySmallSquare;", [ 9642, 0 ] ),
    entity( "&Fopf;", [ 120125, 0 ] ),
    entity( "&ForAll;", [ 8704, 0 ] ),
    entity( "&Fouriertrf;", [ 8497, 0 ] ),
    entity( "&Fscr;", [ 8497, 0 ] ),
    entity( "&GJcy;", [ 1027, 0 ] ),
    entity( "&GT;", [ 62, 0 ] ),
    entity( "&Gamma;", [ 915, 0 ] ),
    entity( "&Gammad;", [ 988, 0 ] ),
    entity( "&Gbreve;", [ 286, 0 ] ),
    entity( "&Gcedil;", [ 290, 0 ] ),
    entity( "&Gcirc;", [ 284, 0 ] ),
    entity( "&Gcy;", [ 1043, 0 ] ),
    entity( "&Gdot;", [ 288, 0 ] ),
    entity( "&Gfr;", [ 120074, 0 ] ),
    entity( "&Gg;", [ 8921, 0 ] ),
    entity( "&Gopf;", [ 120126, 0 ] ),
    entity( "&GreaterEqual;", [ 8805, 0 ] ),
    entity( "&GreaterEqualLess;", [ 8923, 0 ] ),
    entity( "&GreaterFullEqual;", [ 8807, 0 ] ),
    entity( "&GreaterGreater;", [ 10914, 0 ] ),
    entity( "&GreaterLess;", [ 8823, 0 ] ),
    entity( "&GreaterSlantEqual;", [ 10878, 0 ] ),
    entity( "&GreaterTilde;", [ 8819, 0 ] ),
    entity( "&Gscr;", [ 119970, 0 ] ),
    entity( "&Gt;", [ 8811, 0 ] ),
    entity( "&HARDcy;", [ 1066, 0 ] ),
    entity( "&Hacek;", [ 711, 0 ] ),
    entity( "&Hat;", [ 94, 0 ] ),
    entity( "&Hcirc;", [ 292, 0 ] ),
    entity( "&Hfr;", [ 8460, 0 ] ),
    entity( "&HilbertSpace;", [ 8459, 0 ] ),
    entity( "&Hopf;", [ 8461, 0 ] ),
    entity( "&HorizontalLine;", [ 9472, 0 ] ),
    entity( "&Hscr;", [ 8459, 0 ] ),
    entity( "&Hstrok;", [ 294, 0 ] ),
    entity( "&HumpDownHump;", [ 8782, 0 ] ),
    entity( "&HumpEqual;", [ 8783, 0 ] ),
    entity( "&IEcy;", [ 1045, 0 ] ),
    entity( "&IJlig;", [ 306, 0 ] ),
    entity( "&IOcy;", [ 1025, 0 ] ),
    entity( "&Iacute;", [ 205, 0 ] ),
    entity( "&Icirc;", [ 206, 0 ] ),
    entity( "&Icy;", [ 1048, 0 ] ),
    entity( "&Idot;", [ 304, 0 ] ),
    entity( "&Ifr;", [ 8465, 0 ] ),
    entity( "&Igrave;", [ 204, 0 ] ),
    entity( "&Im;", [ 8465, 0 ] ),
    entity( "&Imacr;", [ 298, 0 ] ),
    entity( "&ImaginaryI;", [ 8520, 0 ] ),
    entity( "&Implies;", [ 8658, 0 ] ),
    entity( "&Int;", [ 8748, 0 ] ),
    entity( "&Integral;", [ 8747, 0 ] ),
    entity( "&Intersection;", [ 8898, 0 ] ),
    entity( "&InvisibleComma;", [ 8291, 0 ] ),
    entity( "&InvisibleTimes;", [ 8290, 0 ] ),
    entity( "&Iogon;", [ 302, 0 ] ),
    entity( "&Iopf;", [ 120128, 0 ] ),
    entity( "&Iota;", [ 921, 0 ] ),
    entity( "&Iscr;", [ 8464, 0 ] ),
    entity( "&Itilde;", [ 296, 0 ] ),
    entity( "&Iukcy;", [ 1030, 0 ] ),
    entity( "&Iuml;", [ 207, 0 ] ),
    entity( "&Jcirc;", [ 308, 0 ] ),
    entity( "&Jcy;", [ 1049, 0 ] ),
    entity( "&Jfr;", [ 120077, 0 ] ),
    entity( "&Jopf;", [ 120129, 0 ] ),
    entity( "&Jscr;", [ 119973, 0 ] ),
    entity( "&Jsercy;", [ 1032, 0 ] ),
    entity( "&Jukcy;", [ 1028, 0 ] ),
    entity( "&KHcy;", [ 1061, 0 ] ),
    entity( "&KJcy;", [ 1036, 0 ] ),
    entity( "&Kappa;", [ 922, 0 ] ),
    entity( "&Kcedil;", [ 310, 0 ] ),
    entity( "&Kcy;", [ 1050, 0 ] ),
    entity( "&Kfr;", [ 120078, 0 ] ),
    entity( "&Kopf;", [ 120130, 0 ] ),
    entity( "&Kscr;", [ 119974, 0 ] ),
    entity( "&LJcy;", [ 1033, 0 ] ),
    entity( "&LT;", [ 60, 0 ] ),
    entity( "&Lacute;", [ 313, 0 ] ),
    entity( "&Lambda;", [ 923, 0 ] ),
    entity( "&Lang;", [ 10218, 0 ] ),
    entity( "&Laplacetrf;", [ 8466, 0 ] ),
    entity( "&Larr;", [ 8606, 0 ] ),
    entity( "&Lcaron;", [ 317, 0 ] ),
    entity( "&Lcedil;", [ 315, 0 ] ),
    entity( "&Lcy;", [ 1051, 0 ] ),
    entity( "&LeftAngleBracket;", [ 10216, 0 ] ),
    entity( "&LeftArrow;", [ 8592, 0 ] ),
    entity( "&LeftArrowBar;", [ 8676, 0 ] ),
    entity( "&LeftArrowRightArrow;", [ 8646, 0 ] ),
    entity( "&LeftCeiling;", [ 8968, 0 ] ),
    entity( "&LeftDoubleBracket;", [ 10214, 0 ] ),
    entity( "&LeftDownTeeVector;", [ 10593, 0 ] ),
    entity( "&LeftDownVector;", [ 8643, 0 ] ),
    entity( "&LeftDownVectorBar;", [ 10585, 0 ] ),
    entity( "&LeftFloor;", [ 8970, 0 ] ),
    entity( "&LeftRightArrow;", [ 8596, 0 ] ),
    entity( "&LeftRightVector;", [ 10574, 0 ] ),
    entity( "&LeftTee;", [ 8867, 0 ] ),
    entity( "&LeftTeeArrow;", [ 8612, 0 ] ),
    entity( "&LeftTeeVector;", [ 10586, 0 ] ),
    entity( "&LeftTriangle;", [ 8882, 0 ] ),
    entity( "&LeftTriangleBar;", [ 10703, 0 ] ),
    entity( "&LeftTriangleEqual;", [ 8884, 0 ] ),
    entity( "&LeftUpDownVector;", [ 10577, 0 ] ),
    entity( "&LeftUpTeeVector;", [ 10592, 0 ] ),
    entity( "&LeftUpVector;", [ 8639, 0 ] ),
    entity( "&LeftUpVectorBar;", [ 10584, 0 ] ),
    entity( "&LeftVector;", [ 8636, 0 ] ),
    entity( "&LeftVectorBar;", [ 10578, 0 ] ),
    entity( "&Leftarrow;", [ 8656, 0 ] ),
    entity( "&Leftrightarrow;", [ 8660, 0 ] ),
    entity( "&LessEqualGreater;", [ 8922, 0 ] ),
    entity( "&LessFullEqual;", [ 8806, 0 ] ),
    entity( "&LessGreater;", [ 8822, 0 ] ),
    entity( "&LessLess;", [ 10913, 0 ] ),
    entity( "&LessSlantEqual;", [ 10877, 0 ] ),
    entity( "&LessTilde;", [ 8818, 0 ] ),
    entity( "&Lfr;", [ 120079, 0 ] ),
    entity( "&Ll;", [ 8920, 0 ] ),
    entity( "&Lleftarrow;", [ 8666, 0 ] ),
    entity( "&Lmidot;", [ 319, 0 ] ),
    entity( "&LongLeftArrow;", [ 10229, 0 ] ),
    entity( "&LongLeftRightArrow;", [ 10231, 0 ] ),
    entity( "&LongRightArrow;", [ 10230, 0 ] ),
    entity( "&Longleftarrow;", [ 10232, 0 ] ),
    entity( "&Longleftrightarrow;", [ 10234, 0 ] ),
    entity( "&Longrightarrow;", [ 10233, 0 ] ),
    entity( "&Lopf;", [ 120131, 0 ] ),
    entity( "&LowerLeftArrow;", [ 8601, 0 ] ),
    entity( "&LowerRightArrow;", [ 8600, 0 ] ),
    entity( "&Lscr;", [ 8466, 0 ] ),
    entity( "&Lsh;", [ 8624, 0 ] ),
    entity( "&Lstrok;", [ 321, 0 ] ),
    entity( "&Lt;", [ 8810, 0 ] ),
    entity( "&Map;", [ 10501, 0 ] ),
    entity( "&Mcy;", [ 1052, 0 ] ),
    entity( "&MediumSpace;", [ 8287, 0 ] ),
    entity( "&Mellintrf;", [ 8499, 0 ] ),
    entity( "&Mfr;", [ 120080, 0 ] ),
    entity( "&MinusPlus;", [ 8723, 0 ] ),
    entity( "&Mopf;", [ 120132, 0 ] ),
    entity( "&Mscr;", [ 8499, 0 ] ),
    entity( "&Mu;", [ 924, 0 ] ),
    entity( "&NJcy;", [ 1034, 0 ] ),
    entity( "&Nacute;", [ 323, 0 ] ),
    entity( "&Ncaron;", [ 327, 0 ] ),
    entity( "&Ncedil;", [ 325, 0 ] ),
    entity( "&Ncy;", [ 1053, 0 ] ),
    entity( "&NegativeMediumSpace;", [ 8203, 0 ] ),
    entity( "&NegativeThickSpace;", [ 8203, 0 ] ),
    entity( "&NegativeThinSpace;", [ 8203, 0 ] ),
    entity( "&NegativeVeryThinSpace;", [ 8203, 0 ] ),
    entity( "&NestedGreaterGreater;", [ 8811, 0 ] ),
    entity( "&NestedLessLess;", [ 8810, 0 ] ),
    entity( "&NewLine;", [ 10, 0 ] ),
    entity( "&Nfr;", [ 120081, 0 ] ),
    entity( "&NoBreak;", [ 8288, 0 ] ),
    entity( "&NonBreakingSpace;", [ 160, 0 ] ),
    entity( "&Nopf;", [ 8469, 0 ] ),
    entity( "&Not;", [ 10988, 0 ] ),
    entity( "&NotCongruent;", [ 8802, 0 ] ),
    entity( "&NotCupCap;", [ 8813, 0 ] ),
    entity( "&NotDoubleVerticalBar;", [ 8742, 0 ] ),
    entity( "&NotElement;", [ 8713, 0 ] ),
    entity( "&NotEqual;", [ 8800, 0 ] ),
    entity( "&NotEqualTilde;", [ 8770, 824 ] ),
    entity( "&NotExists;", [ 8708, 0 ] ),
    entity( "&NotGreater;", [ 8815, 0 ] ),
    entity( "&NotGreaterEqual;", [ 8817, 0 ] ),
    entity( "&NotGreaterFullEqual;", [ 8807, 824 ] ),
    entity( "&NotGreaterGreater;", [ 8811, 824 ] ),
    entity( "&NotGreaterLess;", [ 8825, 0 ] ),
    entity( "&NotGreaterSlantEqual;", [ 10878, 824 ] ),
    entity( "&NotGreaterTilde;", [ 8821, 0 ] ),
    entity( "&NotHumpDownHump;", [ 8782, 824 ] ),
    entity( "&NotHumpEqual;", [ 8783, 824 ] ),
    entity( "&NotLeftTriangle;", [ 8938, 0 ] ),
    entity( "&NotLeftTriangleBar;", [ 10703, 824 ] ),
    entity( "&NotLeftTriangleEqual;", [ 8940, 0 ] ),
    entity( "&NotLess;", [ 8814, 0 ] ),
    entity( "&NotLessEqual;", [ 8816, 0 ] ),
    entity( "&NotLessGreater;", [ 8824, 0 ] ),
    entity( "&NotLessLess;", [ 8810, 824 ] ),
    entity( "&NotLessSlantEqual;", [ 10877, 824 ] ),
    entity( "&NotLessTilde;", [ 8820, 0 ] ),
    entity( "&NotNestedGreaterGreater;", [ 10914, 824 ] ),
    entity( "&NotNestedLessLess;", [ 10913, 824 ] ),
    entity( "&NotPrecedes;", [ 8832, 0 ] ),
    entity( "&NotPrecedesEqual;", [ 10927, 824 ] ),
    entity( "&NotPrecedesSlantEqual;", [ 8928, 0 ] ),
    entity( "&NotReverseElement;", [ 8716, 0 ] ),
    entity( "&NotRightTriangle;", [ 8939, 0 ] ),
    entity( "&NotRightTriangleBar;", [ 10704, 824 ] ),
    entity( "&NotRightTriangleEqual;", [ 8941, 0 ] ),
    entity( "&NotSquareSubset;", [ 8847, 824 ] ),
    entity( "&NotSquareSubsetEqual;", [ 8930, 0 ] ),
    entity( "&NotSquareSuperset;", [ 8848, 824 ] ),
    entity( "&NotSquareSupersetEqual;", [ 8931, 0 ] ),
    entity( "&NotSubset;", [ 8834, 8402 ] ),
    entity( "&NotSubsetEqual;", [ 8840, 0 ] ),
    entity( "&NotSucceeds;", [ 8833, 0 ] ),
    entity( "&NotSucceedsEqual;", [ 10928, 824 ] ),
    entity( "&NotSucceedsSlantEqual;", [ 8929, 0 ] ),
    entity( "&NotSucceedsTilde;", [ 8831, 824 ] ),
    entity( "&NotSuperset;", [ 8835, 8402 ] ),
    entity( "&NotSupersetEqual;", [ 8841, 0 ] ),
    entity( "&NotTilde;", [ 8769, 0 ] ),
    entity( "&NotTildeEqual;", [ 8772, 0 ] ),
    entity( "&NotTildeFullEqual;", [ 8775, 0 ] ),
    entity( "&NotTildeTilde;", [ 8777, 0 ] ),
    entity( "&NotVerticalBar;", [ 8740, 0 ] ),
    entity( "&Nscr;", [ 119977, 0 ] ),
    entity( "&Ntilde;", [ 209, 0 ] ),
    entity( "&Nu;", [ 925, 0 ] ),
    entity( "&OElig;", [ 338, 0 ] ),
    entity( "&Oacute;", [ 211, 0 ] ),
    entity( "&Ocirc;", [ 212, 0 ] ),
    entity( "&Ocy;", [ 1054, 0 ] ),
    entity( "&Odblac;", [ 336, 0 ] ),
    entity( "&Ofr;", [ 120082, 0 ] ),
    entity( "&Ograve;", [ 210, 0 ] ),
    entity( "&Omacr;", [ 332, 0 ] ),
    entity( "&Omega;", [ 937, 0 ] ),
    entity( "&Omicron;", [ 927, 0 ] ),
    entity( "&Oopf;", [ 120134, 0 ] ),
    entity( "&OpenCurlyDoubleQuote;", [ 8220, 0 ] ),
    entity( "&OpenCurlyQuote;", [ 8216, 0 ] ),
    entity( "&Or;", [ 10836, 0 ] ),
    entity( "&Oscr;", [ 119978, 0 ] ),
    entity( "&Oslash;", [ 216, 0 ] ),
    entity( "&Otilde;", [ 213, 0 ] ),
    entity( "&Otimes;", [ 10807, 0 ] ),
    entity( "&Ouml;", [ 214, 0 ] ),
    entity( "&OverBar;", [ 8254, 0 ] ),
    entity( "&OverBrace;", [ 9182, 0 ] ),
    entity( "&OverBracket;", [ 9140, 0 ] ),
    entity( "&OverParenthesis;", [ 9180, 0 ] ),
    entity( "&PartialD;", [ 8706, 0 ] ),
    entity( "&Pcy;", [ 1055, 0 ] ),
    entity( "&Pfr;", [ 120083, 0 ] ),
    entity( "&Phi;", [ 934, 0 ] ),
    entity( "&Pi;", [ 928, 0 ] ),
    entity( "&PlusMinus;", [ 177, 0 ] ),
    entity( "&Poincareplane;", [ 8460, 0 ] ),
    entity( "&Popf;", [ 8473, 0 ] ),
    entity( "&Pr;", [ 10939, 0 ] ),
    entity( "&Precedes;", [ 8826, 0 ] ),
    entity( "&PrecedesEqual;", [ 10927, 0 ] ),
    entity( "&PrecedesSlantEqual;", [ 8828, 0 ] ),
    entity( "&PrecedesTilde;", [ 8830, 0 ] ),
    entity( "&Prime;", [ 8243, 0 ] ),
    entity( "&Product;", [ 8719, 0 ] ),
    entity( "&Proportion;", [ 8759, 0 ] ),
    entity( "&Proportional;", [ 8733, 0 ] ),
    entity( "&Pscr;", [ 119979, 0 ] ),
    entity( "&Psi;", [ 936, 0 ] ),
    entity( "&QUOT;", [ 34, 0 ] ),
    entity( "&Qfr;", [ 120084, 0 ] ),
    entity( "&Qopf;", [ 8474, 0 ] ),
    entity( "&Qscr;", [ 119980, 0 ] ),
    entity( "&RBarr;", [ 10512, 0 ] ),
    entity( "&REG;", [ 174, 0 ] ),
    entity( "&Racute;", [ 340, 0 ] ),
    entity( "&Rang;", [ 10219, 0 ] ),
    entity( "&Rarr;", [ 8608, 0 ] ),
    entity( "&Rarrtl;", [ 10518, 0 ] ),
    entity( "&Rcaron;", [ 344, 0 ] ),
    entity( "&Rcedil;", [ 342, 0 ] ),
    entity( "&Rcy;", [ 1056, 0 ] ),
    entity( "&Re;", [ 8476, 0 ] ),
    entity( "&ReverseElement;", [ 8715, 0 ] ),
    entity( "&ReverseEquilibrium;", [ 8651, 0 ] ),
    entity( "&ReverseUpEquilibrium;", [ 10607, 0 ] ),
    entity( "&Rfr;", [ 8476, 0 ] ),
    entity( "&Rho;", [ 929, 0 ] ),
    entity( "&RightAngleBracket;", [ 10217, 0 ] ),
    entity( "&RightArrow;", [ 8594, 0 ] ),
    entity( "&RightArrowBar;", [ 8677, 0 ] ),
    entity( "&RightArrowLeftArrow;", [ 8644, 0 ] ),
    entity( "&RightCeiling;", [ 8969, 0 ] ),
    entity( "&RightDoubleBracket;", [ 10215, 0 ] ),
    entity( "&RightDownTeeVector;", [ 10589, 0 ] ),
    entity( "&RightDownVector;", [ 8642, 0 ] ),
    entity( "&RightDownVectorBar;", [ 10581, 0 ] ),
    entity( "&RightFloor;", [ 8971, 0 ] ),
    entity( "&RightTee;", [ 8866, 0 ] ),
    entity( "&RightTeeArrow;", [ 8614, 0 ] ),
    entity( "&RightTeeVector;", [ 10587, 0 ] ),
    entity( "&RightTriangle;", [ 8883, 0 ] ),
    entity( "&RightTriangleBar;", [ 10704, 0 ] ),
    entity( "&RightTriangleEqual;", [ 8885, 0 ] ),
    entity( "&RightUpDownVector;", [ 10575, 0 ] ),
    entity( "&RightUpTeeVector;", [ 10588, 0 ] ),
    entity( "&RightUpVector;", [ 8638, 0 ] ),
    entity( "&RightUpVectorBar;", [ 10580, 0 ] ),
    entity( "&RightVector;", [ 8640, 0 ] ),
    entity( "&RightVectorBar;", [ 10579, 0 ] ),
    entity( "&Rightarrow;", [ 8658, 0 ] ),
    entity( "&Ropf;", [ 8477, 0 ] ),
    entity( "&RoundImplies;", [ 10608, 0 ] ),
    entity( "&Rrightarrow;", [ 8667, 0 ] ),
    entity( "&Rscr;", [ 8475, 0 ] ),
    entity( "&Rsh;", [ 8625, 0 ] ),
    entity( "&RuleDelayed;", [ 10740, 0 ] ),
    entity( "&SHCHcy;", [ 1065, 0 ] ),
    entity( "&SHcy;", [ 1064, 0 ] ),
    entity( "&SOFTcy;", [ 1068, 0 ] ),
    entity( "&Sacute;", [ 346, 0 ] ),
    entity( "&Sc;", [ 10940, 0 ] ),
    entity( "&Scaron;", [ 352, 0 ] ),
    entity( "&Scedil;", [ 350, 0 ] ),
    entity( "&Scirc;", [ 348, 0 ] ),
    entity( "&Scy;", [ 1057, 0 ] ),
    entity( "&Sfr;", [ 120086, 0 ] ),
    entity( "&ShortDownArrow;", [ 8595, 0 ] ),
    entity( "&ShortLeftArrow;", [ 8592, 0 ] ),
    entity( "&ShortRightArrow;", [ 8594, 0 ] ),
    entity( "&ShortUpArrow;", [ 8593, 0 ] ),
    entity( "&Sigma;", [ 931, 0 ] ),
    entity( "&SmallCircle;", [ 8728, 0 ] ),
    entity( "&Sopf;", [ 120138, 0 ] ),
    entity( "&Sqrt;", [ 8730, 0 ] ),
    entity( "&Square;", [ 9633, 0 ] ),
    entity( "&SquareIntersection;", [ 8851, 0 ] ),
    entity( "&SquareSubset;", [ 8847, 0 ] ),
    entity( "&SquareSubsetEqual;", [ 8849, 0 ] ),
    entity( "&SquareSuperset;", [ 8848, 0 ] ),
    entity( "&SquareSupersetEqual;", [ 8850, 0 ] ),
    entity( "&SquareUnion;", [ 8852, 0 ] ),
    entity( "&Sscr;", [ 119982, 0 ] ),
    entity( "&Star;", [ 8902, 0 ] ),
    entity( "&Sub;", [ 8912, 0 ] ),
    entity( "&Subset;", [ 8912, 0 ] ),
    entity( "&SubsetEqual;", [ 8838, 0 ] ),
    entity( "&Succeeds;", [ 8827, 0 ] ),
    entity( "&SucceedsEqual;", [ 10928, 0 ] ),
    entity( "&SucceedsSlantEqual;", [ 8829, 0 ] ),
    entity( "&SucceedsTilde;", [ 8831, 0 ] ),
    entity( "&SuchThat;", [ 8715, 0 ] ),
    entity( "&Sum;", [ 8721, 0 ] ),
    entity( "&Sup;", [ 8913, 0 ] ),
    entity( "&Superset;", [ 8835, 0 ] ),
    entity( "&SupersetEqual;", [ 8839, 0 ] ),
    entity( "&Supset;", [ 8913, 0 ] ),
    entity( "&THORN;", [ 222, 0 ] ),
    entity( "&TRADE;", [ 8482, 0 ] ),
    entity( "&TSHcy;", [ 1035, 0 ] ),
    entity( "&TScy;", [ 1062, 0 ] ),
    entity( "&Tab;", [ 9, 0 ] ),
    entity( "&Tau;", [ 932, 0 ] ),
    entity( "&Tcaron;", [ 356, 0 ] ),
    entity( "&Tcedil;", [ 354, 0 ] ),
    entity( "&Tcy;", [ 1058, 0 ] ),
    entity( "&Tfr;", [ 120087, 0 ] ),
    entity( "&Therefore;", [ 8756, 0 ] ),
    entity( "&Theta;", [ 920, 0 ] ),
    entity( "&ThickSpace;", [ 8287, 8202 ] ),
    entity( "&ThinSpace;", [ 8201, 0 ] ),
    entity( "&Tilde;", [ 8764, 0 ] ),
    entity( "&TildeEqual;", [ 8771, 0 ] ),
    entity( "&TildeFullEqual;", [ 8773, 0 ] ),
    entity( "&TildeTilde;", [ 8776, 0 ] ),
    entity( "&Topf;", [ 120139, 0 ] ),
    entity( "&TripleDot;", [ 8411, 0 ] ),
    entity( "&Tscr;", [ 119983, 0 ] ),
    entity( "&Tstrok;", [ 358, 0 ] ),
    entity( "&Uacute;", [ 218, 0 ] ),
    entity( "&Uarr;", [ 8607, 0 ] ),
    entity( "&Uarrocir;", [ 10569, 0 ] ),
    entity( "&Ubrcy;", [ 1038, 0 ] ),
    entity( "&Ubreve;", [ 364, 0 ] ),
    entity( "&Ucirc;", [ 219, 0 ] ),
    entity( "&Ucy;", [ 1059, 0 ] ),
    entity( "&Udblac;", [ 368, 0 ] ),
    entity( "&Ufr;", [ 120088, 0 ] ),
    entity( "&Ugrave;", [ 217, 0 ] ),
    entity( "&Umacr;", [ 362, 0 ] ),
    entity( "&UnderBar;", [ 95, 0 ] ),
    entity( "&UnderBrace;", [ 9183, 0 ] ),
    entity( "&UnderBracket;", [ 9141, 0 ] ),
    entity( "&UnderParenthesis;", [ 9181, 0 ] ),
    entity( "&Union;", [ 8899, 0 ] ),
    entity( "&UnionPlus;", [ 8846, 0 ] ),
    entity( "&Uogon;", [ 370, 0 ] ),
    entity( "&Uopf;", [ 120140, 0 ] ),
    entity( "&UpArrow;", [ 8593, 0 ] ),
    entity( "&UpArrowBar;", [ 10514, 0 ] ),
    entity( "&UpArrowDownArrow;", [ 8645, 0 ] ),
    entity( "&UpDownArrow;", [ 8597, 0 ] ),
    entity( "&UpEquilibrium;", [ 10606, 0 ] ),
    entity( "&UpTee;", [ 8869, 0 ] ),
    entity( "&UpTeeArrow;", [ 8613, 0 ] ),
    entity( "&Uparrow;", [ 8657, 0 ] ),
    entity( "&Updownarrow;", [ 8661, 0 ] ),
    entity( "&UpperLeftArrow;", [ 8598, 0 ] ),
    entity( "&UpperRightArrow;", [ 8599, 0 ] ),
    entity( "&Upsi;", [ 978, 0 ] ),
    entity( "&Upsilon;", [ 933, 0 ] ),
    entity( "&Uring;", [ 366, 0 ] ),
    entity( "&Uscr;", [ 119984, 0 ] ),
    entity( "&Utilde;", [ 360, 0 ] ),
    entity( "&Uuml;", [ 220, 0 ] ),
    entity( "&VDash;", [ 8875, 0 ] ),
    entity( "&Vbar;", [ 10987, 0 ] ),
    entity( "&Vcy;", [ 1042, 0 ] ),
    entity( "&Vdash;", [ 8873, 0 ] ),
    entity( "&Vdashl;", [ 10982, 0 ] ),
    entity( "&Vee;", [ 8897, 0 ] ),
    entity( "&Verbar;", [ 8214, 0 ] ),
    entity( "&Vert;", [ 8214, 0 ] ),
    entity( "&VerticalBar;", [ 8739, 0 ] ),
    entity( "&VerticalLine;", [ 124, 0 ] ),
    entity( "&VerticalSeparator;", [ 10072, 0 ] ),
    entity( "&VerticalTilde;", [ 8768, 0 ] ),
    entity( "&VeryThinSpace;", [ 8202, 0 ] ),
    entity( "&Vfr;", [ 120089, 0 ] ),
    entity( "&Vopf;", [ 120141, 0 ] ),
    entity( "&Vscr;", [ 119985, 0 ] ),
    entity( "&Vvdash;", [ 8874, 0 ] ),
    entity( "&Wcirc;", [ 372, 0 ] ),
    entity( "&Wedge;", [ 8896, 0 ] ),
    entity( "&Wfr;", [ 120090, 0 ] ),
    entity( "&Wopf;", [ 120142, 0 ] ),
    entity( "&Wscr;", [ 119986, 0 ] ),
    entity( "&Xfr;", [ 120091, 0 ] ),
    entity( "&Xi;", [ 926, 0 ] ),
    entity( "&Xopf;", [ 120143, 0 ] ),
    entity( "&Xscr;", [ 119987, 0 ] ),
    entity( "&YAcy;", [ 1071, 0 ] ),
    entity( "&YIcy;", [ 1031, 0 ] ),
    entity( "&YUcy;", [ 1070, 0 ] ),
    entity( "&Yacute;", [ 221, 0 ] ),
    entity( "&Ycirc;", [ 374, 0 ] ),
    entity( "&Ycy;", [ 1067, 0 ] ),
    entity( "&Yfr;", [ 120092, 0 ] ),
    entity( "&Yopf;", [ 120144, 0 ] ),
    entity( "&Yscr;", [ 119988, 0 ] ),
    entity( "&Yuml;", [ 376, 0 ] ),
    entity( "&ZHcy;", [ 1046, 0 ] ),
    entity( "&Zacute;", [ 377, 0 ] ),
    entity( "&Zcaron;", [ 381, 0 ] ),
    entity( "&Zcy;", [ 1047, 0 ] ),
    entity( "&Zdot;", [ 379, 0 ] ),
    entity( "&ZeroWidthSpace;", [ 8203, 0 ] ),
    entity( "&Zeta;", [ 918, 0 ] ),
    entity( "&Zfr;", [ 8488, 0 ] ),
    entity( "&Zopf;", [ 8484, 0 ] ),
    entity( "&Zscr;", [ 119989, 0 ] ),
    entity( "&aacute;", [ 225, 0 ] ),
    entity( "&abreve;", [ 259, 0 ] ),
    entity( "&ac;", [ 8766, 0 ] ),
    entity( "&acE;", [ 8766, 819 ] ),
    entity( "&acd;", [ 8767, 0 ] ),
    entity( "&acirc;", [ 226, 0 ] ),
    entity( "&acute;", [ 180, 0 ] ),
    entity( "&acy;", [ 1072, 0 ] ),
    entity( "&aelig;", [ 230, 0 ] ),
    entity( "&af;", [ 8289, 0 ] ),
    entity( "&afr;", [ 120094, 0 ] ),
    entity( "&agrave;", [ 224, 0 ] ),
    entity( "&alefsym;", [ 8501, 0 ] ),
    entity( "&aleph;", [ 8501, 0 ] ),
    entity( "&alpha;", [ 945, 0 ] ),
    entity( "&amacr;", [ 257, 0 ] ),
    entity( "&amalg;", [ 10815, 0 ] ),
    entity( "&amp;", [ 38, 0 ] ),
    entity( "&and;", [ 8743, 0 ] ),
    entity( "&andand;", [ 10837, 0 ] ),
    entity( "&andd;", [ 10844, 0 ] ),
    entity( "&andslope;", [ 10840, 0 ] ),
    entity( "&andv;", [ 10842, 0 ] ),
    entity( "&ang;", [ 8736, 0 ] ),
    entity( "&ange;", [ 10660, 0 ] ),
    entity( "&angle;", [ 8736, 0 ] ),
    entity( "&angmsd;", [ 8737, 0 ] ),
    entity( "&angmsdaa;", [ 10664, 0 ] ),
    entity( "&angmsdab;", [ 10665, 0 ] ),
    entity( "&angmsdac;", [ 10666, 0 ] ),
    entity( "&angmsdad;", [ 10667, 0 ] ),
    entity( "&angmsdae;", [ 10668, 0 ] ),
    entity( "&angmsdaf;", [ 10669, 0 ] ),
    entity( "&angmsdag;", [ 10670, 0 ] ),
    entity( "&angmsdah;", [ 10671, 0 ] ),
    entity( "&angrt;", [ 8735, 0 ] ),
    entity( "&angrtvb;", [ 8894, 0 ] ),
    entity( "&angrtvbd;", [ 10653, 0 ] ),
    entity( "&angsph;", [ 8738, 0 ] ),
    entity( "&angst;", [ 197, 0 ] ),
    entity( "&angzarr;", [ 9084, 0 ] ),
    entity( "&aogon;", [ 261, 0 ] ),
    entity( "&aopf;", [ 120146, 0 ] ),
    entity( "&ap;", [ 8776, 0 ] ),
    entity( "&apE;", [ 10864, 0 ] ),
    entity( "&apacir;", [ 10863, 0 ] ),
    entity( "&ape;", [ 8778, 0 ] ),
    entity( "&apid;", [ 8779, 0 ] ),
    entity( "&apos;", [ 39, 0 ] ),
    entity( "&approx;", [ 8776, 0 ] ),
    entity( "&approxeq;", [ 8778, 0 ] ),
    entity( "&aring;", [ 229, 0 ] ),
    entity( "&ascr;", [ 119990, 0 ] ),
    entity( "&ast;", [ 42, 0 ] ),
    entity( "&asymp;", [ 8776, 0 ] ),
    entity( "&asympeq;", [ 8781, 0 ] ),
    entity( "&atilde;", [ 227, 0 ] ),
    entity( "&auml;", [ 228, 0 ] ),
    entity( "&awconint;", [ 8755, 0 ] ),
    entity( "&awint;", [ 10769, 0 ] ),
    entity( "&bNot;", [ 10989, 0 ] ),
    entity( "&backcong;", [ 8780, 0 ] ),
    entity( "&backepsilon;", [ 1014, 0 ] ),
    entity( "&backprime;", [ 8245, 0 ] ),
    entity( "&backsim;", [ 8765, 0 ] ),
    entity( "&backsimeq;", [ 8909, 0 ] ),
    entity( "&barvee;", [ 8893, 0 ] ),
    entity( "&barwed;", [ 8965, 0 ] ),
    entity( "&barwedge;", [ 8965, 0 ] ),
    entity( "&bbrk;", [ 9141, 0 ] ),
    entity( "&bbrktbrk;", [ 9142, 0 ] ),
    entity( "&bcong;", [ 8780, 0 ] ),
    entity( "&bcy;", [ 1073, 0 ] ),
    entity( "&bdquo;", [ 8222, 0 ] ),
    entity( "&becaus;", [ 8757, 0 ] ),
    entity( "&because;", [ 8757, 0 ] ),
    entity( "&bemptyv;", [ 10672, 0 ] ),
    entity( "&bepsi;", [ 1014, 0 ] ),
    entity( "&bernou;", [ 8492, 0 ] ),
    entity( "&beta;", [ 946, 0 ] ),
    entity( "&beth;", [ 8502, 0 ] ),
    entity( "&between;", [ 8812, 0 ] ),
    entity( "&bfr;", [ 120095, 0 ] ),
    entity( "&bigcap;", [ 8898, 0 ] ),
    entity( "&bigcirc;", [ 9711, 0 ] ),
    entity( "&bigcup;", [ 8899, 0 ] ),
    entity( "&bigodot;", [ 10752, 0 ] ),
    entity( "&bigoplus;", [ 10753, 0 ] ),
    entity( "&bigotimes;", [ 10754, 0 ] ),
    entity( "&bigsqcup;", [ 10758, 0 ] ),
    entity( "&bigstar;", [ 9733, 0 ] ),
    entity( "&bigtriangledown;", [ 9661, 0 ] ),
    entity( "&bigtriangleup;", [ 9651, 0 ] ),
    entity( "&biguplus;", [ 10756, 0 ] ),
    entity( "&bigvee;", [ 8897, 0 ] ),
    entity( "&bigwedge;", [ 8896, 0 ] ),
    entity( "&bkarow;", [ 10509, 0 ] ),
    entity( "&blacklozenge;", [ 10731, 0 ] ),
    entity( "&blacksquare;", [ 9642, 0 ] ),
    entity( "&blacktriangle;", [ 9652, 0 ] ),
    entity( "&blacktriangledown;", [ 9662, 0 ] ),
    entity( "&blacktriangleleft;", [ 9666, 0 ] ),
    entity( "&blacktriangleright;", [ 9656, 0 ] ),
    entity( "&blank;", [ 9251, 0 ] ),
    entity( "&blk12;", [ 9618, 0 ] ),
    entity( "&blk14;", [ 9617, 0 ] ),
    entity( "&blk34;", [ 9619, 0 ] ),
    entity( "&block;", [ 9608, 0 ] ),
    entity( "&bne;", [ 61, 8421 ] ),
    entity( "&bnequiv;", [ 8801, 8421 ] ),
    entity( "&bnot;", [ 8976, 0 ] ),
    entity( "&bopf;", [ 120147, 0 ] ),
    entity( "&bot;", [ 8869, 0 ] ),
    entity( "&bottom;", [ 8869, 0 ] ),
    entity( "&bowtie;", [ 8904, 0 ] ),
    entity( "&boxDL;", [ 9559, 0 ] ),
    entity( "&boxDR;", [ 9556, 0 ] ),
    entity( "&boxDl;", [ 9558, 0 ] ),
    entity( "&boxDr;", [ 9555, 0 ] ),
    entity( "&boxH;", [ 9552, 0 ] ),
    entity( "&boxHD;", [ 9574, 0 ] ),
    entity( "&boxHU;", [ 9577, 0 ] ),
    entity( "&boxHd;", [ 9572, 0 ] ),
    entity( "&boxHu;", [ 9575, 0 ] ),
    entity( "&boxUL;", [ 9565, 0 ] ),
    entity( "&boxUR;", [ 9562, 0 ] ),
    entity( "&boxUl;", [ 9564, 0 ] ),
    entity( "&boxUr;", [ 9561, 0 ] ),
    entity( "&boxV;", [ 9553, 0 ] ),
    entity( "&boxVH;", [ 9580, 0 ] ),
    entity( "&boxVL;", [ 9571, 0 ] ),
    entity( "&boxVR;", [ 9568, 0 ] ),
    entity( "&boxVh;", [ 9579, 0 ] ),
    entity( "&boxVl;", [ 9570, 0 ] ),
    entity( "&boxVr;", [ 9567, 0 ] ),
    entity( "&boxbox;", [ 10697, 0 ] ),
    entity( "&boxdL;", [ 9557, 0 ] ),
    entity( "&boxdR;", [ 9554, 0 ] ),
    entity( "&boxdl;", [ 9488, 0 ] ),
    entity( "&boxdr;", [ 9484, 0 ] ),
    entity( "&boxh;", [ 9472, 0 ] ),
    entity( "&boxhD;", [ 9573, 0 ] ),
    entity( "&boxhU;", [ 9576, 0 ] ),
    entity( "&boxhd;", [ 9516, 0 ] ),
    entity( "&boxhu;", [ 9524, 0 ] ),
    entity( "&boxminus;", [ 8863, 0 ] ),
    entity( "&boxplus;", [ 8862, 0 ] ),
    entity( "&boxtimes;", [ 8864, 0 ] ),
    entity( "&boxuL;", [ 9563, 0 ] ),
    entity( "&boxuR;", [ 9560, 0 ] ),
    entity( "&boxul;", [ 9496, 0 ] ),
    entity( "&boxur;", [ 9492, 0 ] ),
    entity( "&boxv;", [ 9474, 0 ] ),
    entity( "&boxvH;", [ 9578, 0 ] ),
    entity( "&boxvL;", [ 9569, 0 ] ),
    entity( "&boxvR;", [ 9566, 0 ] ),
    entity( "&boxvh;", [ 9532, 0 ] ),
    entity( "&boxvl;", [ 9508, 0 ] ),
    entity( "&boxvr;", [ 9500, 0 ] ),
    entity( "&bprime;", [ 8245, 0 ] ),
    entity( "&breve;", [ 728, 0 ] ),
    entity( "&brvbar;", [ 166, 0 ] ),
    entity( "&bscr;", [ 119991, 0 ] ),
    entity( "&bsemi;", [ 8271, 0 ] ),
    entity( "&bsim;", [ 8765, 0 ] ),
    entity( "&bsime;", [ 8909, 0 ] ),
    entity( "&bsol;", [ 92, 0 ] ),
    entity( "&bsolb;", [ 10693, 0 ] ),
    entity( "&bsolhsub;", [ 10184, 0 ] ),
    entity( "&bull;", [ 8226, 0 ] ),
    entity( "&bullet;", [ 8226, 0 ] ),
    entity( "&bump;", [ 8782, 0 ] ),
    entity( "&bumpE;", [ 10926, 0 ] ),
    entity( "&bumpe;", [ 8783, 0 ] ),
    entity( "&bumpeq;", [ 8783, 0 ] ),
    entity( "&cacute;", [ 263, 0 ] ),
    entity( "&cap;", [ 8745, 0 ] ),
    entity( "&capand;", [ 10820, 0 ] ),
    entity( "&capbrcup;", [ 10825, 0 ] ),
    entity( "&capcap;", [ 10827, 0 ] ),
    entity( "&capcup;", [ 10823, 0 ] ),
    entity( "&capdot;", [ 10816, 0 ] ),
    entity( "&caps;", [ 8745, 65024 ] ),
    entity( "&caret;", [ 8257, 0 ] ),
    entity( "&caron;", [ 711, 0 ] ),
    entity( "&ccaps;", [ 10829, 0 ] ),
    entity( "&ccaron;", [ 269, 0 ] ),
    entity( "&ccedil;", [ 231, 0 ] ),
    entity( "&ccirc;", [ 265, 0 ] ),
    entity( "&ccups;", [ 10828, 0 ] ),
    entity( "&ccupssm;", [ 10832, 0 ] ),
    entity( "&cdot;", [ 267, 0 ] ),
    entity( "&cedil;", [ 184, 0 ] ),
    entity( "&cemptyv;", [ 10674, 0 ] ),
    entity( "&cent;", [ 162, 0 ] ),
    entity( "&centerdot;", [ 183, 0 ] ),
    entity( "&cfr;", [ 120096, 0 ] ),
    entity( "&chcy;", [ 1095, 0 ] ),
    entity( "&check;", [ 10003, 0 ] ),
    entity( "&checkmark;", [ 10003, 0 ] ),
    entity( "&chi;", [ 967, 0 ] ),
    entity( "&cir;", [ 9675, 0 ] ),
    entity( "&cirE;", [ 10691, 0 ] ),
    entity( "&circ;", [ 710, 0 ] ),
    entity( "&circeq;", [ 8791, 0 ] ),
    entity( "&circlearrowleft;", [ 8634, 0 ] ),
    entity( "&circlearrowright;", [ 8635, 0 ] ),
    entity( "&circledR;", [ 174, 0 ] ),
    entity( "&circledS;", [ 9416, 0 ] ),
    entity( "&circledast;", [ 8859, 0 ] ),
    entity( "&circledcirc;", [ 8858, 0 ] ),
    entity( "&circleddash;", [ 8861, 0 ] ),
    entity( "&cire;", [ 8791, 0 ] ),
    entity( "&cirfnint;", [ 10768, 0 ] ),
    entity( "&cirmid;", [ 10991, 0 ] ),
    entity( "&cirscir;", [ 10690, 0 ] ),
    entity( "&clubs;", [ 9827, 0 ] ),
    entity( "&clubsuit;", [ 9827, 0 ] ),
    entity( "&colon;", [ 58, 0 ] ),
    entity( "&colone;", [ 8788, 0 ] ),
    entity( "&coloneq;", [ 8788, 0 ] ),
    entity( "&comma;", [ 44, 0 ] ),
    entity( "&commat;", [ 64, 0 ] ),
    entity( "&comp;", [ 8705, 0 ] ),
    entity( "&compfn;", [ 8728, 0 ] ),
    entity( "&complement;", [ 8705, 0 ] ),
    entity( "&complexes;", [ 8450, 0 ] ),
    entity( "&cong;", [ 8773, 0 ] ),
    entity( "&congdot;", [ 10861, 0 ] ),
    entity( "&conint;", [ 8750, 0 ] ),
    entity( "&copf;", [ 120148, 0 ] ),
    entity( "&coprod;", [ 8720, 0 ] ),
    entity( "&copy;", [ 169, 0 ] ),
    entity( "&copysr;", [ 8471, 0 ] ),
    entity( "&crarr;", [ 8629, 0 ] ),
    entity( "&cross;", [ 10007, 0 ] ),
    entity( "&cscr;", [ 119992, 0 ] ),
    entity( "&csub;", [ 10959, 0 ] ),
    entity( "&csube;", [ 10961, 0 ] ),
    entity( "&csup;", [ 10960, 0 ] ),
    entity( "&csupe;", [ 10962, 0 ] ),
    entity( "&ctdot;", [ 8943, 0 ] ),
    entity( "&cudarrl;", [ 10552, 0 ] ),
    entity( "&cudarrr;", [ 10549, 0 ] ),
    entity( "&cuepr;", [ 8926, 0 ] ),
    entity( "&cuesc;", [ 8927, 0 ] ),
    entity( "&cularr;", [ 8630, 0 ] ),
    entity( "&cularrp;", [ 10557, 0 ] ),
    entity( "&cup;", [ 8746, 0 ] ),
    entity( "&cupbrcap;", [ 10824, 0 ] ),
    entity( "&cupcap;", [ 10822, 0 ] ),
    entity( "&cupcup;", [ 10826, 0 ] ),
    entity( "&cupdot;", [ 8845, 0 ] ),
    entity( "&cupor;", [ 10821, 0 ] ),
    entity( "&cups;", [ 8746, 65024 ] ),
    entity( "&curarr;", [ 8631, 0 ] ),
    entity( "&curarrm;", [ 10556, 0 ] ),
    entity( "&curlyeqprec;", [ 8926, 0 ] ),
    entity( "&curlyeqsucc;", [ 8927, 0 ] ),
    entity( "&curlyvee;", [ 8910, 0 ] ),
    entity( "&curlywedge;", [ 8911, 0 ] ),
    entity( "&curren;", [ 164, 0 ] ),
    entity( "&curvearrowleft;", [ 8630, 0 ] ),
    entity( "&curvearrowright;", [ 8631, 0 ] ),
    entity( "&cuvee;", [ 8910, 0 ] ),
    entity( "&cuwed;", [ 8911, 0 ] ),
    entity( "&cwconint;", [ 8754, 0 ] ),
    entity( "&cwint;", [ 8753, 0 ] ),
    entity( "&cylcty;", [ 9005, 0 ] ),
    entity( "&dArr;", [ 8659, 0 ] ),
    entity( "&dHar;", [ 10597, 0 ] ),
    entity( "&dagger;", [ 8224, 0 ] ),
    entity( "&daleth;", [ 8504, 0 ] ),
    entity( "&darr;", [ 8595, 0 ] ),
    entity( "&dash;", [ 8208, 0 ] ),
    entity( "&dashv;", [ 8867, 0 ] ),
    entity( "&dbkarow;", [ 10511, 0 ] ),
    entity( "&dblac;", [ 733, 0 ] ),
    entity( "&dcaron;", [ 271, 0 ] ),
    entity( "&dcy;", [ 1076, 0 ] ),
    entity( "&dd;", [ 8518, 0 ] ),
    entity( "&ddagger;", [ 8225, 0 ] ),
    entity( "&ddarr;", [ 8650, 0 ] ),
    entity( "&ddotseq;", [ 10871, 0 ] ),
    entity( "&deg;", [ 176, 0 ] ),
    entity( "&delta;", [ 948, 0 ] ),
    entity( "&demptyv;", [ 10673, 0 ] ),
    entity( "&dfisht;", [ 10623, 0 ] ),
    entity( "&dfr;", [ 120097, 0 ] ),
    entity( "&dharl;", [ 8643, 0 ] ),
    entity( "&dharr;", [ 8642, 0 ] ),
    entity( "&diam;", [ 8900, 0 ] ),
    entity( "&diamond;", [ 8900, 0 ] ),
    entity( "&diamondsuit;", [ 9830, 0 ] ),
    entity( "&diams;", [ 9830, 0 ] ),
    entity( "&die;", [ 168, 0 ] ),
    entity( "&digamma;", [ 989, 0 ] ),
    entity( "&disin;", [ 8946, 0 ] ),
    entity( "&div;", [ 247, 0 ] ),
    entity( "&divide;", [ 247, 0 ] ),
    entity( "&divideontimes;", [ 8903, 0 ] ),
    entity( "&divonx;", [ 8903, 0 ] ),
    entity( "&djcy;", [ 1106, 0 ] ),
    entity( "&dlcorn;", [ 8990, 0 ] ),
    entity( "&dlcrop;", [ 8973, 0 ] ),
    entity( "&dollar;", [ 36, 0 ] ),
    entity( "&dopf;", [ 120149, 0 ] ),
    entity( "&dot;", [ 729, 0 ] ),
    entity( "&doteq;", [ 8784, 0 ] ),
    entity( "&doteqdot;", [ 8785, 0 ] ),
    entity( "&dotminus;", [ 8760, 0 ] ),
    entity( "&dotplus;", [ 8724, 0 ] ),
    entity( "&dotsquare;", [ 8865, 0 ] ),
    entity( "&doublebarwedge;", [ 8966, 0 ] ),
    entity( "&downarrow;", [ 8595, 0 ] ),
    entity( "&downdownarrows;", [ 8650, 0 ] ),
    entity( "&downharpoonleft;", [ 8643, 0 ] ),
    entity( "&downharpoonright;", [ 8642, 0 ] ),
    entity( "&drbkarow;", [ 10512, 0 ] ),
    entity( "&drcorn;", [ 8991, 0 ] ),
    entity( "&drcrop;", [ 8972, 0 ] ),
    entity( "&dscr;", [ 119993, 0 ] ),
    entity( "&dscy;", [ 1109, 0 ] ),
    entity( "&dsol;", [ 10742, 0 ] ),
    entity( "&dstrok;", [ 273, 0 ] ),
    entity( "&dtdot;", [ 8945, 0 ] ),
    entity( "&dtri;", [ 9663, 0 ] ),
    entity( "&dtrif;", [ 9662, 0 ] ),
    entity( "&duarr;", [ 8693, 0 ] ),
    entity( "&duhar;", [ 10607, 0 ] ),
    entity( "&dwangle;", [ 10662, 0 ] ),
    entity( "&dzcy;", [ 1119, 0 ] ),
    entity( "&dzigrarr;", [ 10239, 0 ] ),
    entity( "&eDDot;", [ 10871, 0 ] ),
    entity( "&eDot;", [ 8785, 0 ] ),
    entity( "&eacute;", [ 233, 0 ] ),
    entity( "&easter;", [ 10862, 0 ] ),
    entity( "&ecaron;", [ 283, 0 ] ),
    entity( "&ecir;", [ 8790, 0 ] ),
    entity( "&ecirc;", [ 234, 0 ] ),
    entity( "&ecolon;", [ 8789, 0 ] ),
    entity( "&ecy;", [ 1101, 0 ] ),
    entity( "&edot;", [ 279, 0 ] ),
    entity( "&ee;", [ 8519, 0 ] ),
    entity( "&efDot;", [ 8786, 0 ] ),
    entity( "&efr;", [ 120098, 0 ] ),
    entity( "&eg;", [ 10906, 0 ] ),
    entity( "&egrave;", [ 232, 0 ] ),
    entity( "&egs;", [ 10902, 0 ] ),
    entity( "&egsdot;", [ 10904, 0 ] ),
    entity( "&el;", [ 10905, 0 ] ),
    entity( "&elinters;", [ 9191, 0 ] ),
    entity( "&ell;", [ 8467, 0 ] ),
    entity( "&els;", [ 10901, 0 ] ),
    entity( "&elsdot;", [ 10903, 0 ] ),
    entity( "&emacr;", [ 275, 0 ] ),
    entity( "&empty;", [ 8709, 0 ] ),
    entity( "&emptyset;", [ 8709, 0 ] ),
    entity( "&emptyv;", [ 8709, 0 ] ),
    entity( "&emsp13;", [ 8196, 0 ] ),
    entity( "&emsp14;", [ 8197, 0 ] ),
    entity( "&emsp;", [ 8195, 0 ] ),
    entity( "&eng;", [ 331, 0 ] ),
    entity( "&ensp;", [ 8194, 0 ] ),
    entity( "&eogon;", [ 281, 0 ] ),
    entity( "&eopf;", [ 120150, 0 ] ),
    entity( "&epar;", [ 8917, 0 ] ),
    entity( "&eparsl;", [ 10723, 0 ] ),
    entity( "&eplus;", [ 10865, 0 ] ),
    entity( "&epsi;", [ 949, 0 ] ),
    entity( "&epsilon;", [ 949, 0 ] ),
    entity( "&epsiv;", [ 1013, 0 ] ),
    entity( "&eqcirc;", [ 8790, 0 ] ),
    entity( "&eqcolon;", [ 8789, 0 ] ),
    entity( "&eqsim;", [ 8770, 0 ] ),
    entity( "&eqslantgtr;", [ 10902, 0 ] ),
    entity( "&eqslantless;", [ 10901, 0 ] ),
    entity( "&equals;", [ 61, 0 ] ),
    entity( "&equest;", [ 8799, 0 ] ),
    entity( "&equiv;", [ 8801, 0 ] ),
    entity( "&equivDD;", [ 10872, 0 ] ),
    entity( "&eqvparsl;", [ 10725, 0 ] ),
    entity( "&erDot;", [ 8787, 0 ] ),
    entity( "&erarr;", [ 10609, 0 ] ),
    entity( "&escr;", [ 8495, 0 ] ),
    entity( "&esdot;", [ 8784, 0 ] ),
    entity( "&esim;", [ 8770, 0 ] ),
    entity( "&eta;", [ 951, 0 ] ),
    entity( "&eth;", [ 240, 0 ] ),
    entity( "&euml;", [ 235, 0 ] ),
    entity( "&euro;", [ 8364, 0 ] ),
    entity( "&excl;", [ 33, 0 ] ),
    entity( "&exist;", [ 8707, 0 ] ),
    entity( "&expectation;", [ 8496, 0 ] ),
    entity( "&exponentiale;", [ 8519, 0 ] ),
    entity( "&fallingdotseq;", [ 8786, 0 ] ),
    entity( "&fcy;", [ 1092, 0 ] ),
    entity( "&female;", [ 9792, 0 ] ),
    entity( "&ffilig;", [ 64259, 0 ] ),
    entity( "&fflig;", [ 64256, 0 ] ),
    entity( "&ffllig;", [ 64260, 0 ] ),
    entity( "&ffr;", [ 120099, 0 ] ),
    entity( "&filig;", [ 64257, 0 ] ),
    entity( "&fjlig;", [ 102, 106 ] ),
    entity( "&flat;", [ 9837, 0 ] ),
    entity( "&fllig;", [ 64258, 0 ] ),
    entity( "&fltns;", [ 9649, 0 ] ),
    entity( "&fnof;", [ 402, 0 ] ),
    entity( "&fopf;", [ 120151, 0 ] ),
    entity( "&forall;", [ 8704, 0 ] ),
    entity( "&fork;", [ 8916, 0 ] ),
    entity( "&forkv;", [ 10969, 0 ] ),
    entity( "&fpartint;", [ 10765, 0 ] ),
    entity( "&frac12", [ 189, 0 ] ),
    entity( "&frac12;", [ 189, 0 ] ),
    entity( "&frac13;", [ 8531, 0 ] ),
    entity( "&frac14",  [ 188, 0 ] ),
    entity( "&frac14;", [ 188, 0 ] ),
    entity( "&frac15;", [ 8533, 0 ] ),
    entity( "&frac16;", [ 8537, 0 ] ),
    entity( "&frac18;", [ 8539, 0 ] ),
    entity( "&frac23;", [ 8532, 0 ] ),
    entity( "&frac25;", [ 8534, 0 ] ),
    entity( "&frac34",  [ 190, 0 ] ),
    entity( "&frac34;", [ 190, 0 ] ),
    entity( "&frac35;", [ 8535, 0 ] ),
    entity( "&frac38;", [ 8540, 0 ] ),
    entity( "&frac45;", [ 8536, 0 ] ),
    entity( "&frac56;", [ 8538, 0 ] ),
    entity( "&frac58;", [ 8541, 0 ] ),
    entity( "&frac78;", [ 8542, 0 ] ),
    entity( "&frasl;", [ 8260, 0 ] ),
    entity( "&frown;", [ 8994, 0 ] ),
    entity( "&fscr;", [ 119995, 0 ] ),
    entity( "&gE;", [ 8807, 0 ] ),
    entity( "&gEl;", [ 10892, 0 ] ),
    entity( "&gacute;", [ 501, 0 ] ),
    entity( "&gamma;", [ 947, 0 ] ),
    entity( "&gammad;", [ 989, 0 ] ),
    entity( "&gap;", [ 10886, 0 ] ),
    entity( "&gbreve;", [ 287, 0 ] ),
    entity( "&gcirc;", [ 285, 0 ] ),
    entity( "&gcy;", [ 1075, 0 ] ),
    entity( "&gdot;", [ 289, 0 ] ),
    entity( "&ge;", [ 8805, 0 ] ),
    entity( "&gel;", [ 8923, 0 ] ),
    entity( "&geq;", [ 8805, 0 ] ),
    entity( "&geqq;", [ 8807, 0 ] ),
    entity( "&geqslant;", [ 10878, 0 ] ),
    entity( "&ges;", [ 10878, 0 ] ),
    entity( "&gescc;", [ 10921, 0 ] ),
    entity( "&gesdot;", [ 10880, 0 ] ),
    entity( "&gesdoto;", [ 10882, 0 ] ),
    entity( "&gesdotol;", [ 10884, 0 ] ),
    entity( "&gesl;", [ 8923, 65024 ] ),
    entity( "&gesles;", [ 10900, 0 ] ),
    entity( "&gfr;", [ 120100, 0 ] ),
    entity( "&gg;", [ 8811, 0 ] ),
    entity( "&ggg;", [ 8921, 0 ] ),
    entity( "&gimel;", [ 8503, 0 ] ),
    entity( "&gjcy;", [ 1107, 0 ] ),
    entity( "&gl;", [ 8823, 0 ] ),
    entity( "&glE;", [ 10898, 0 ] ),
    entity( "&gla;", [ 10917, 0 ] ),
    entity( "&glj;", [ 10916, 0 ] ),
    entity( "&gnE;", [ 8809, 0 ] ),
    entity( "&gnap;", [ 10890, 0 ] ),
    entity( "&gnapprox;", [ 10890, 0 ] ),
    entity( "&gne;", [ 10888, 0 ] ),
    entity( "&gneq;", [ 10888, 0 ] ),
    entity( "&gneqq;", [ 8809, 0 ] ),
    entity( "&gnsim;", [ 8935, 0 ] ),
    entity( "&gopf;", [ 120152, 0 ] ),
    entity( "&grave;", [ 96, 0 ] ),
    entity( "&gscr;", [ 8458, 0 ] ),
    entity( "&gsim;", [ 8819, 0 ] ),
    entity( "&gsime;", [ 10894, 0 ] ),
    entity( "&gsiml;", [ 10896, 0 ] ),
    entity( "&gt;", [ 62, 0 ] ),
    entity( "&gtcc;", [ 10919, 0 ] ),
    entity( "&gtcir;", [ 10874, 0 ] ),
    entity( "&gtdot;", [ 8919, 0 ] ),
    entity( "&gtlPar;", [ 10645, 0 ] ),
    entity( "&gtquest;", [ 10876, 0 ] ),
    entity( "&gtrapprox;", [ 10886, 0 ] ),
    entity( "&gtrarr;", [ 10616, 0 ] ),
    entity( "&gtrdot;", [ 8919, 0 ] ),
    entity( "&gtreqless;", [ 8923, 0 ] ),
    entity( "&gtreqqless;", [ 10892, 0 ] ),
    entity( "&gtrless;", [ 8823, 0 ] ),
    entity( "&gtrsim;", [ 8819, 0 ] ),
    entity( "&gvertneqq;", [ 8809, 65024 ] ),
    entity( "&gvnE;", [ 8809, 65024 ] ),
    entity( "&hArr;", [ 8660, 0 ] ),
    entity( "&hairsp;", [ 8202, 0 ] ),
    entity( "&half;", [ 189, 0 ] ),
    entity( "&hamilt;", [ 8459, 0 ] ),
    entity( "&hardcy;", [ 1098, 0 ] ),
    entity( "&harr;", [ 8596, 0 ] ),
    entity( "&harrcir;", [ 10568, 0 ] ),
    entity( "&harrw;", [ 8621, 0 ] ),
    entity( "&hbar;", [ 8463, 0 ] ),
    entity( "&hcirc;", [ 293, 0 ] ),
    entity( "&hearts;", [ 9829, 0 ] ),
    entity( "&heartsuit;", [ 9829, 0 ] ),
    entity( "&hellip;", [ 8230, 0 ] ),
    entity( "&hercon;", [ 8889, 0 ] ),
    entity( "&hfr;", [ 120101, 0 ] ),
    entity( "&hksearow;", [ 10533, 0 ] ),
    entity( "&hkswarow;", [ 10534, 0 ] ),
    entity( "&hoarr;", [ 8703, 0 ] ),
    entity( "&homtht;", [ 8763, 0 ] ),
    entity( "&hookleftarrow;", [ 8617, 0 ] ),
    entity( "&hookrightarrow;", [ 8618, 0 ] ),
    entity( "&hopf;", [ 120153, 0 ] ),
    entity( "&horbar;", [ 8213, 0 ] ),
    entity( "&hscr;", [ 119997, 0 ] ),
    entity( "&hslash;", [ 8463, 0 ] ),
    entity( "&hstrok;", [ 295, 0 ] ),
    entity( "&hybull;", [ 8259, 0 ] ),
    entity( "&hyphen;", [ 8208, 0 ] ),
    entity( "&iacute;", [ 237, 0 ] ),
    entity( "&ic;", [ 8291, 0 ] ),
    entity( "&icirc;", [ 238, 0 ] ),
    entity( "&icy;", [ 1080, 0 ] ),
    entity( "&iecy;", [ 1077, 0 ] ),
    entity( "&iexcl;", [ 161, 0 ] ),
    entity( "&iff;", [ 8660, 0 ] ),
    entity( "&ifr;", [ 120102, 0 ] ),
    entity( "&igrave;", [ 236, 0 ] ),
    entity( "&ii;", [ 8520, 0 ] ),
    entity( "&iiiint;", [ 10764, 0 ] ),
    entity( "&iiint;", [ 8749, 0 ] ),
    entity( "&iinfin;", [ 10716, 0 ] ),
    entity( "&iiota;", [ 8489, 0 ] ),
    entity( "&ijlig;", [ 307, 0 ] ),
    entity( "&imacr;", [ 299, 0 ] ),
    entity( "&image;", [ 8465, 0 ] ),
    entity( "&imagline;", [ 8464, 0 ] ),
    entity( "&imagpart;", [ 8465, 0 ] ),
    entity( "&imath;", [ 305, 0 ] ),
    entity( "&imof;", [ 8887, 0 ] ),
    entity( "&imped;", [ 437, 0 ] ),
    entity( "&in;", [ 8712, 0 ] ),
    entity( "&incare;", [ 8453, 0 ] ),
    entity( "&infin;", [ 8734, 0 ] ),
    entity( "&infintie;", [ 10717, 0 ] ),
    entity( "&inodot;", [ 305, 0 ] ),
    entity( "&int;", [ 8747, 0 ] ),
    entity( "&intcal;", [ 8890, 0 ] ),
    entity( "&integers;", [ 8484, 0 ] ),
    entity( "&intercal;", [ 8890, 0 ] ),
    entity( "&intlarhk;", [ 10775, 0 ] ),
    entity( "&intprod;", [ 10812, 0 ] ),
    entity( "&iocy;", [ 1105, 0 ] ),
    entity( "&iogon;", [ 303, 0 ] ),
    entity( "&iopf;", [ 120154, 0 ] ),
    entity( "&iota;", [ 953, 0 ] ),
    entity( "&iprod;", [ 10812, 0 ] ),
    entity( "&iquest;", [ 191, 0 ] ),
    entity( "&iscr;", [ 119998, 0 ] ),
    entity( "&isin;", [ 8712, 0 ] ),
    entity( "&isinE;", [ 8953, 0 ] ),
    entity( "&isindot;", [ 8949, 0 ] ),
    entity( "&isins;", [ 8948, 0 ] ),
    entity( "&isinsv;", [ 8947, 0 ] ),
    entity( "&isinv;", [ 8712, 0 ] ),
    entity( "&it;", [ 8290, 0 ] ),
    entity( "&itilde;", [ 297, 0 ] ),
    entity( "&iukcy;", [ 1110, 0 ] ),
    entity( "&iuml;", [ 239, 0 ] ),
    entity( "&jcirc;", [ 309, 0 ] ),
    entity( "&jcy;", [ 1081, 0 ] ),
    entity( "&jfr;", [ 120103, 0 ] ),
    entity( "&jmath;", [ 567, 0 ] ),
    entity( "&jopf;", [ 120155, 0 ] ),
    entity( "&jscr;", [ 119999, 0 ] ),
    entity( "&jsercy;", [ 1112, 0 ] ),
    entity( "&jukcy;", [ 1108, 0 ] ),
    entity( "&kappa;", [ 954, 0 ] ),
    entity( "&kappav;", [ 1008, 0 ] ),
    entity( "&kcedil;", [ 311, 0 ] ),
    entity( "&kcy;", [ 1082, 0 ] ),
    entity( "&kfr;", [ 120104, 0 ] ),
    entity( "&kgreen;", [ 312, 0 ] ),
    entity( "&khcy;", [ 1093, 0 ] ),
    entity( "&kjcy;", [ 1116, 0 ] ),
    entity( "&kopf;", [ 120156, 0 ] ),
    entity( "&kscr;", [ 120000, 0 ] ),
    entity( "&lAarr;", [ 8666, 0 ] ),
    entity( "&lArr;", [ 8656, 0 ] ),
    entity( "&lAtail;", [ 10523, 0 ] ),
    entity( "&lBarr;", [ 10510, 0 ] ),
    entity( "&lE;", [ 8806, 0 ] ),
    entity( "&lEg;", [ 10891, 0 ] ),
    entity( "&lHar;", [ 10594, 0 ] ),
    entity( "&lacute;", [ 314, 0 ] ),
    entity( "&laemptyv;", [ 10676, 0 ] ),
    entity( "&lagran;", [ 8466, 0 ] ),
    entity( "&lambda;", [ 955, 0 ] ),
    entity( "&lang;", [ 10216, 0 ] ),
    entity( "&langd;", [ 10641, 0 ] ),
    entity( "&langle;", [ 10216, 0 ] ),
    entity( "&lap;", [ 10885, 0 ] ),
    entity( "&laquo;", [ 171, 0 ] ),
    entity( "&larr;", [ 8592, 0 ] ),
    entity( "&larrb;", [ 8676, 0 ] ),
    entity( "&larrbfs;", [ 10527, 0 ] ),
    entity( "&larrfs;", [ 10525, 0 ] ),
    entity( "&larrhk;", [ 8617, 0 ] ),
    entity( "&larrlp;", [ 8619, 0 ] ),
    entity( "&larrpl;", [ 10553, 0 ] ),
    entity( "&larrsim;", [ 10611, 0 ] ),
    entity( "&larrtl;", [ 8610, 0 ] ),
    entity( "&lat;", [ 10923, 0 ] ),
    entity( "&latail;", [ 10521, 0 ] ),
    entity( "&late;", [ 10925, 0 ] ),
    entity( "&lates;", [ 10925, 65024 ] ),
    entity( "&lbarr;", [ 10508, 0 ] ),
    entity( "&lbbrk;", [ 10098, 0 ] ),
    entity( "&lbrace;", [ 123, 0 ] ),
    entity( "&lbrack;", [ 91, 0 ] ),
    entity( "&lbrke;", [ 10635, 0 ] ),
    entity( "&lbrksld;", [ 10639, 0 ] ),
    entity( "&lbrkslu;", [ 10637, 0 ] ),
    entity( "&lcaron;", [ 318, 0 ] ),
    entity( "&lcedil;", [ 316, 0 ] ),
    entity( "&lceil;", [ 8968, 0 ] ),
    entity( "&lcub;", [ 123, 0 ] ),
    entity( "&lcy;", [ 1083, 0 ] ),
    entity( "&ldca;", [ 10550, 0 ] ),
    entity( "&ldquo;", [ 8220, 0 ] ),
    entity( "&ldquor;", [ 8222, 0 ] ),
    entity( "&ldrdhar;", [ 10599, 0 ] ),
    entity( "&ldrushar;", [ 10571, 0 ] ),
    entity( "&ldsh;", [ 8626, 0 ] ),
    entity( "&le;", [ 8804, 0 ] ),
    entity( "&leftarrow;", [ 8592, 0 ] ),
    entity( "&leftarrowtail;", [ 8610, 0 ] ),
    entity( "&leftharpoondown;", [ 8637, 0 ] ),
    entity( "&leftharpoonup;", [ 8636, 0 ] ),
    entity( "&leftleftarrows;", [ 8647, 0 ] ),
    entity( "&leftrightarrow;", [ 8596, 0 ] ),
    entity( "&leftrightarrows;", [ 8646, 0 ] ),
    entity( "&leftrightharpoons;", [ 8651, 0 ] ),
    entity( "&leftrightsquigarrow;", [ 8621, 0 ] ),
    entity( "&leftthreetimes;", [ 8907, 0 ] ),
    entity( "&leg;", [ 8922, 0 ] ),
    entity( "&leq;", [ 8804, 0 ] ),
    entity( "&leqq;", [ 8806, 0 ] ),
    entity( "&leqslant;", [ 10877, 0 ] ),
    entity( "&les;", [ 10877, 0 ] ),
    entity( "&lescc;", [ 10920, 0 ] ),
    entity( "&lesdot;", [ 10879, 0 ] ),
    entity( "&lesdoto;", [ 10881, 0 ] ),
    entity( "&lesdotor;", [ 10883, 0 ] ),
    entity( "&lesg;", [ 8922, 65024 ] ),
    entity( "&lesges;", [ 10899, 0 ] ),
    entity( "&lessapprox;", [ 10885, 0 ] ),
    entity( "&lessdot;", [ 8918, 0 ] ),
    entity( "&lesseqgtr;", [ 8922, 0 ] ),
    entity( "&lesseqqgtr;", [ 10891, 0 ] ),
    entity( "&lessgtr;", [ 8822, 0 ] ),
    entity( "&lesssim;", [ 8818, 0 ] ),
    entity( "&lfisht;", [ 10620, 0 ] ),
    entity( "&lfloor;", [ 8970, 0 ] ),
    entity( "&lfr;", [ 120105, 0 ] ),
    entity( "&lg;", [ 8822, 0 ] ),
    entity( "&lgE;", [ 10897, 0 ] ),
    entity( "&lhard;", [ 8637, 0 ] ),
    entity( "&lharu;", [ 8636, 0 ] ),
    entity( "&lharul;", [ 10602, 0 ] ),
    entity( "&lhblk;", [ 9604, 0 ] ),
    entity( "&ljcy;", [ 1113, 0 ] ),
    entity( "&ll;", [ 8810, 0 ] ),
    entity( "&llarr;", [ 8647, 0 ] ),
    entity( "&llcorner;", [ 8990, 0 ] ),
    entity( "&llhard;", [ 10603, 0 ] ),
    entity( "&lltri;", [ 9722, 0 ] ),
    entity( "&lmidot;", [ 320, 0 ] ),
    entity( "&lmoust;", [ 9136, 0 ] ),
    entity( "&lmoustache;", [ 9136, 0 ] ),
    entity( "&lnE;", [ 8808, 0 ] ),
    entity( "&lnap;", [ 10889, 0 ] ),
    entity( "&lnapprox;", [ 10889, 0 ] ),
    entity( "&lne;", [ 10887, 0 ] ),
    entity( "&lneq;", [ 10887, 0 ] ),
    entity( "&lneqq;", [ 8808, 0 ] ),
    entity( "&lnsim;", [ 8934, 0 ] ),
    entity( "&loang;", [ 10220, 0 ] ),
    entity( "&loarr;", [ 8701, 0 ] ),
    entity( "&lobrk;", [ 10214, 0 ] ),
    entity( "&longleftarrow;", [ 10229, 0 ] ),
    entity( "&longleftrightarrow;", [ 10231, 0 ] ),
    entity( "&longmapsto;", [ 10236, 0 ] ),
    entity( "&longrightarrow;", [ 10230, 0 ] ),
    entity( "&looparrowleft;", [ 8619, 0 ] ),
    entity( "&looparrowright;", [ 8620, 0 ] ),
    entity( "&lopar;", [ 10629, 0 ] ),
    entity( "&lopf;", [ 120157, 0 ] ),
    entity( "&loplus;", [ 10797, 0 ] ),
    entity( "&lotimes;", [ 10804, 0 ] ),
    entity( "&lowast;", [ 8727, 0 ] ),
    entity( "&lowbar;", [ 95, 0 ] ),
    entity( "&loz;", [ 9674, 0 ] ),
    entity( "&lozenge;", [ 9674, 0 ] ),
    entity( "&lozf;", [ 10731, 0 ] ),
    entity( "&lpar;", [ 40, 0 ] ),
    entity( "&lparlt;", [ 10643, 0 ] ),
    entity( "&lrarr;", [ 8646, 0 ] ),
    entity( "&lrcorner;", [ 8991, 0 ] ),
    entity( "&lrhar;", [ 8651, 0 ] ),
    entity( "&lrhard;", [ 10605, 0 ] ),
    entity( "&lrm;", [ 8206, 0 ] ),
    entity( "&lrtri;", [ 8895, 0 ] ),
    entity( "&lsaquo;", [ 8249, 0 ] ),
    entity( "&lscr;", [ 120001, 0 ] ),
    entity( "&lsh;", [ 8624, 0 ] ),
    entity( "&lsim;", [ 8818, 0 ] ),
    entity( "&lsime;", [ 10893, 0 ] ),
    entity( "&lsimg;", [ 10895, 0 ] ),
    entity( "&lsqb;", [ 91, 0 ] ),
    entity( "&lsquo;", [ 8216, 0 ] ),
    entity( "&lsquor;", [ 8218, 0 ] ),
    entity( "&lstrok;", [ 322, 0 ] ),
    entity( "&lt;", [ 60, 0 ] ),
    entity( "&ltcc;", [ 10918, 0 ] ),
    entity( "&ltcir;", [ 10873, 0 ] ),
    entity( "&ltdot;", [ 8918, 0 ] ),
    entity( "&lthree;", [ 8907, 0 ] ),
    entity( "&ltimes;", [ 8905, 0 ] ),
    entity( "&ltlarr;", [ 10614, 0 ] ),
    entity( "&ltquest;", [ 10875, 0 ] ),
    entity( "&ltrPar;", [ 10646, 0 ] ),
    entity( "&ltri;", [ 9667, 0 ] ),
    entity( "&ltrie;", [ 8884, 0 ] ),
    entity( "&ltrif;", [ 9666, 0 ] ),
    entity( "&lurdshar;", [ 10570, 0 ] ),
    entity( "&luruhar;", [ 10598, 0 ] ),
    entity( "&lvertneqq;", [ 8808, 65024 ] ),
    entity( "&lvnE;", [ 8808, 65024 ] ),
    entity( "&mDDot;", [ 8762, 0 ] ),
    entity( "&macr;", [ 175, 0 ] ),
    entity( "&male;", [ 9794, 0 ] ),
    entity( "&malt;", [ 10016, 0 ] ),
    entity( "&maltese;", [ 10016, 0 ] ),
    entity( "&map;", [ 8614, 0 ] ),
    entity( "&mapsto;", [ 8614, 0 ] ),
    entity( "&mapstodown;", [ 8615, 0 ] ),
    entity( "&mapstoleft;", [ 8612, 0 ] ),
    entity( "&mapstoup;", [ 8613, 0 ] ),
    entity( "&marker;", [ 9646, 0 ] ),
    entity( "&mcomma;", [ 10793, 0 ] ),
    entity( "&mcy;", [ 1084, 0 ] ),
    entity( "&mdash;", [ 8212, 0 ] ),
    entity( "&measuredangle;", [ 8737, 0 ] ),
    entity( "&mfr;", [ 120106, 0 ] ),
    entity( "&mho;", [ 8487, 0 ] ),
    entity( "&micro;", [ 181, 0 ] ),
    entity( "&mid;", [ 8739, 0 ] ),
    entity( "&midast;", [ 42, 0 ] ),
    entity( "&midcir;", [ 10992, 0 ] ),
    entity( "&middot;", [ 183, 0 ] ),
    entity( "&minus;", [ 8722, 0 ] ),
    entity( "&minusb;", [ 8863, 0 ] ),
    entity( "&minusd;", [ 8760, 0 ] ),
    entity( "&minusdu;", [ 10794, 0 ] ),
    entity( "&mlcp;", [ 10971, 0 ] ),
    entity( "&mldr;", [ 8230, 0 ] ),
    entity( "&mnplus;", [ 8723, 0 ] ),
    entity( "&models;", [ 8871, 0 ] ),
    entity( "&mopf;", [ 120158, 0 ] ),
    entity( "&mp;", [ 8723, 0 ] ),
    entity( "&mscr;", [ 120002, 0 ] ),
    entity( "&mstpos;", [ 8766, 0 ] ),
    entity( "&mu;", [ 956, 0 ] ),
    entity( "&multimap;", [ 8888, 0 ] ),
    entity( "&mumap;", [ 8888, 0 ] ),
    entity( "&nGg;", [ 8921, 824 ] ),
    entity( "&nGt;", [ 8811, 8402 ] ),
    entity( "&nGtv;", [ 8811, 824 ] ),
    entity( "&nLeftarrow;", [ 8653, 0 ] ),
    entity( "&nLeftrightarrow;", [ 8654, 0 ] ),
    entity( "&nLl;", [ 8920, 824 ] ),
    entity( "&nLt;", [ 8810, 8402 ] ),
    entity( "&nLtv;", [ 8810, 824 ] ),
    entity( "&nRightarrow;", [ 8655, 0 ] ),
    entity( "&nVDash;", [ 8879, 0 ] ),
    entity( "&nVdash;", [ 8878, 0 ] ),
    entity( "&nabla;", [ 8711, 0 ] ),
    entity( "&nacute;", [ 324, 0 ] ),
    entity( "&nang;", [ 8736, 8402 ] ),
    entity( "&nap;", [ 8777, 0 ] ),
    entity( "&napE;", [ 10864, 824 ] ),
    entity( "&napid;", [ 8779, 824 ] ),
    entity( "&napos;", [ 329, 0 ] ),
    entity( "&napprox;", [ 8777, 0 ] ),
    entity( "&natur;", [ 9838, 0 ] ),
    entity( "&natural;", [ 9838, 0 ] ),
    entity( "&naturals;", [ 8469, 0 ] ),
    entity( "&nbsp;", [ 160, 0 ] ),
    entity( "&nbump;", [ 8782, 824 ] ),
    entity( "&nbumpe;", [ 8783, 824 ] ),
    entity( "&ncap;", [ 10819, 0 ] ),
    entity( "&ncaron;", [ 328, 0 ] ),
    entity( "&ncedil;", [ 326, 0 ] ),
    entity( "&ncong;", [ 8775, 0 ] ),
    entity( "&ncongdot;", [ 10861, 824 ] ),
    entity( "&ncup;", [ 10818, 0 ] ),
    entity( "&ncy;", [ 1085, 0 ] ),
    entity( "&ndash;", [ 8211, 0 ] ),
    entity( "&ne;", [ 8800, 0 ] ),
    entity( "&neArr;", [ 8663, 0 ] ),
    entity( "&nearhk;", [ 10532, 0 ] ),
    entity( "&nearr;", [ 8599, 0 ] ),
    entity( "&nearrow;", [ 8599, 0 ] ),
    entity( "&nedot;", [ 8784, 824 ] ),
    entity( "&nequiv;", [ 8802, 0 ] ),
    entity( "&nesear;", [ 10536, 0 ] ),
    entity( "&nesim;", [ 8770, 824 ] ),
    entity( "&nexist;", [ 8708, 0 ] ),
    entity( "&nexists;", [ 8708, 0 ] ),
    entity( "&nfr;", [ 120107, 0 ] ),
    entity( "&ngE;", [ 8807, 824 ] ),
    entity( "&nge;", [ 8817, 0 ] ),
    entity( "&ngeq;", [ 8817, 0 ] ),
    entity( "&ngeqq;", [ 8807, 824 ] ),
    entity( "&ngeqslant;", [ 10878, 824 ] ),
    entity( "&nges;", [ 10878, 824 ] ),
    entity( "&ngsim;", [ 8821, 0 ] ),
    entity( "&ngt;", [ 8815, 0 ] ),
    entity( "&ngtr;", [ 8815, 0 ] ),
    entity( "&nhArr;", [ 8654, 0 ] ),
    entity( "&nharr;", [ 8622, 0 ] ),
    entity( "&nhpar;", [ 10994, 0 ] ),
    entity( "&ni;", [ 8715, 0 ] ),
    entity( "&nis;", [ 8956, 0 ] ),
    entity( "&nisd;", [ 8954, 0 ] ),
    entity( "&niv;", [ 8715, 0 ] ),
    entity( "&njcy;", [ 1114, 0 ] ),
    entity( "&nlArr;", [ 8653, 0 ] ),
    entity( "&nlE;", [ 8806, 824 ] ),
    entity( "&nlarr;", [ 8602, 0 ] ),
    entity( "&nldr;", [ 8229, 0 ] ),
    entity( "&nle;", [ 8816, 0 ] ),
    entity( "&nleftarrow;", [ 8602, 0 ] ),
    entity( "&nleftrightarrow;", [ 8622, 0 ] ),
    entity( "&nleq;", [ 8816, 0 ] ),
    entity( "&nleqq;", [ 8806, 824 ] ),
    entity( "&nleqslant;", [ 10877, 824 ] ),
    entity( "&nles;", [ 10877, 824 ] ),
    entity( "&nless;", [ 8814, 0 ] ),
    entity( "&nlsim;", [ 8820, 0 ] ),
    entity( "&nlt;", [ 8814, 0 ] ),
    entity( "&nltri;", [ 8938, 0 ] ),
    entity( "&nltrie;", [ 8940, 0 ] ),
    entity( "&nmid;", [ 8740, 0 ] ),
    entity( "&nopf;", [ 120159, 0 ] ),
    entity( "&not;", [ 172, 0 ] ),
    entity( "&notin;", [ 8713, 0 ] ),
    entity( "&notinE;", [ 8953, 824 ] ),
    entity( "&notindot;", [ 8949, 824 ] ),
    entity( "&notinva;", [ 8713, 0 ] ),
    entity( "&notinvb;", [ 8951, 0 ] ),
    entity( "&notinvc;", [ 8950, 0 ] ),
    entity( "&notni;", [ 8716, 0 ] ),
    entity( "&notniva;", [ 8716, 0 ] ),
    entity( "&notnivb;", [ 8958, 0 ] ),
    entity( "&notnivc;", [ 8957, 0 ] ),
    entity( "&npar;", [ 8742, 0 ] ),
    entity( "&nparallel;", [ 8742, 0 ] ),
    entity( "&nparsl;", [ 11005, 8421 ] ),
    entity( "&npart;", [ 8706, 824 ] ),
    entity( "&npolint;", [ 10772, 0 ] ),
    entity( "&npr;", [ 8832, 0 ] ),
    entity( "&nprcue;", [ 8928, 0 ] ),
    entity( "&npre;", [ 10927, 824 ] ),
    entity( "&nprec;", [ 8832, 0 ] ),
    entity( "&npreceq;", [ 10927, 824 ] ),
    entity( "&nrArr;", [ 8655, 0 ] ),
    entity( "&nrarr;", [ 8603, 0 ] ),
    entity( "&nrarrc;", [ 10547, 824 ] ),
    entity( "&nrarrw;", [ 8605, 824 ] ),
    entity( "&nrightarrow;", [ 8603, 0 ] ),
    entity( "&nrtri;", [ 8939, 0 ] ),
    entity( "&nrtrie;", [ 8941, 0 ] ),
    entity( "&nsc;", [ 8833, 0 ] ),
    entity( "&nsccue;", [ 8929, 0 ] ),
    entity( "&nsce;", [ 10928, 824 ] ),
    entity( "&nscr;", [ 120003, 0 ] ),
    entity( "&nshortmid;", [ 8740, 0 ] ),
    entity( "&nshortparallel;", [ 8742, 0 ] ),
    entity( "&nsim;", [ 8769, 0 ] ),
    entity( "&nsime;", [ 8772, 0 ] ),
    entity( "&nsimeq;", [ 8772, 0 ] ),
    entity( "&nsmid;", [ 8740, 0 ] ),
    entity( "&nspar;", [ 8742, 0 ] ),
    entity( "&nsqsube;", [ 8930, 0 ] ),
    entity( "&nsqsupe;", [ 8931, 0 ] ),
    entity( "&nsub;", [ 8836, 0 ] ),
    entity( "&nsubE;", [ 10949, 824 ] ),
    entity( "&nsube;", [ 8840, 0 ] ),
    entity( "&nsubset;", [ 8834, 8402 ] ),
    entity( "&nsubseteq;", [ 8840, 0 ] ),
    entity( "&nsubseteqq;", [ 10949, 824 ] ),
    entity( "&nsucc;", [ 8833, 0 ] ),
    entity( "&nsucceq;", [ 10928, 824 ] ),
    entity( "&nsup;", [ 8837, 0 ] ),
    entity( "&nsupE;", [ 10950, 824 ] ),
    entity( "&nsupe;", [ 8841, 0 ] ),
    entity( "&nsupset;", [ 8835, 8402 ] ),
    entity( "&nsupseteq;", [ 8841, 0 ] ),
    entity( "&nsupseteqq;", [ 10950, 824 ] ),
    entity( "&ntgl;", [ 8825, 0 ] ),
    entity( "&ntilde;", [ 241, 0 ] ),
    entity( "&ntlg;", [ 8824, 0 ] ),
    entity( "&ntriangleleft;", [ 8938, 0 ] ),
    entity( "&ntrianglelefteq;", [ 8940, 0 ] ),
    entity( "&ntriangleright;", [ 8939, 0 ] ),
    entity( "&ntrianglerighteq;", [ 8941, 0 ] ),
    entity( "&nu;", [ 957, 0 ] ),
    entity( "&num;", [ 35, 0 ] ),
    entity( "&numero;", [ 8470, 0 ] ),
    entity( "&numsp;", [ 8199, 0 ] ),
    entity( "&nvDash;", [ 8877, 0 ] ),
    entity( "&nvHarr;", [ 10500, 0 ] ),
    entity( "&nvap;", [ 8781, 8402 ] ),
    entity( "&nvdash;", [ 8876, 0 ] ),
    entity( "&nvge;", [ 8805, 8402 ] ),
    entity( "&nvgt;", [ 62, 8402 ] ),
    entity( "&nvinfin;", [ 10718, 0 ] ),
    entity( "&nvlArr;", [ 10498, 0 ] ),
    entity( "&nvle;", [ 8804, 8402 ] ),
    entity( "&nvlt;", [ 60, 8402 ] ),
    entity( "&nvltrie;", [ 8884, 8402 ] ),
    entity( "&nvrArr;", [ 10499, 0 ] ),
    entity( "&nvrtrie;", [ 8885, 8402 ] ),
    entity( "&nvsim;", [ 8764, 8402 ] ),
    entity( "&nwArr;", [ 8662, 0 ] ),
    entity( "&nwarhk;", [ 10531, 0 ] ),
    entity( "&nwarr;", [ 8598, 0 ] ),
    entity( "&nwarrow;", [ 8598, 0 ] ),
    entity( "&nwnear;", [ 10535, 0 ] ),
    entity( "&oS;", [ 9416, 0 ] ),
    entity( "&oacute;", [ 243, 0 ] ),
    entity( "&oast;", [ 8859, 0 ] ),
    entity( "&ocir;", [ 8858, 0 ] ),
    entity( "&ocirc;", [ 244, 0 ] ),
    entity( "&ocy;", [ 1086, 0 ] ),
    entity( "&odash;", [ 8861, 0 ] ),
    entity( "&odblac;", [ 337, 0 ] ),
    entity( "&odiv;", [ 10808, 0 ] ),
    entity( "&odot;", [ 8857, 0 ] ),
    entity( "&odsold;", [ 10684, 0 ] ),
    entity( "&oelig;", [ 339, 0 ] ),
    entity( "&ofcir;", [ 10687, 0 ] ),
    entity( "&ofr;", [ 120108, 0 ] ),
    entity( "&ogon;", [ 731, 0 ] ),
    entity( "&ograve;", [ 242, 0 ] ),
    entity( "&ogt;", [ 10689, 0 ] ),
    entity( "&ohbar;", [ 10677, 0 ] ),
    entity( "&ohm;", [ 937, 0 ] ),
    entity( "&oint;", [ 8750, 0 ] ),
    entity( "&olarr;", [ 8634, 0 ] ),
    entity( "&olcir;", [ 10686, 0 ] ),
    entity( "&olcross;", [ 10683, 0 ] ),
    entity( "&oline;", [ 8254, 0 ] ),
    entity( "&olt;", [ 10688, 0 ] ),
    entity( "&omacr;", [ 333, 0 ] ),
    entity( "&omega;", [ 969, 0 ] ),
    entity( "&omicron;", [ 959, 0 ] ),
    entity( "&omid;", [ 10678, 0 ] ),
    entity( "&ominus;", [ 8854, 0 ] ),
    entity( "&oopf;", [ 120160, 0 ] ),
    entity( "&opar;", [ 10679, 0 ] ),
    entity( "&operp;", [ 10681, 0 ] ),
    entity( "&oplus;", [ 8853, 0 ] ),
    entity( "&or;", [ 8744, 0 ] ),
    entity( "&orarr;", [ 8635, 0 ] ),
    entity( "&ord;", [ 10845, 0 ] ),
    entity( "&order;", [ 8500, 0 ] ),
    entity( "&orderof;", [ 8500, 0 ] ),
    entity( "&ordf;", [ 170, 0 ] ),
    entity( "&ordm;", [ 186, 0 ] ),
    entity( "&origof;", [ 8886, 0 ] ),
    entity( "&oror;", [ 10838, 0 ] ),
    entity( "&orslope;", [ 10839, 0 ] ),
    entity( "&orv;", [ 10843, 0 ] ),
    entity( "&oscr;", [ 8500, 0 ] ),
    entity( "&oslash;", [ 248, 0 ] ),
    entity( "&osol;", [ 8856, 0 ] ),
    entity( "&otilde;", [ 245, 0 ] ),
    entity( "&otimes;", [ 8855, 0 ] ),
    entity( "&otimesas;", [ 10806, 0 ] ),
    entity( "&ouml;", [ 246, 0 ] ),
    entity( "&ovbar;", [ 9021, 0 ] ),
    entity( "&par;", [ 8741, 0 ] ),
    entity( "&para;", [ 182, 0 ] ),
    entity( "&parallel;", [ 8741, 0 ] ),
    entity( "&parsim;", [ 10995, 0 ] ),
    entity( "&parsl;", [ 11005, 0 ] ),
    entity( "&part;", [ 8706, 0 ] ),
    entity( "&pcy;", [ 1087, 0 ] ),
    entity( "&percnt;", [ 37, 0 ] ),
    entity( "&period;", [ 46, 0 ] ),
    entity( "&permil;", [ 8240, 0 ] ),
    entity( "&perp;", [ 8869, 0 ] ),
    entity( "&pertenk;", [ 8241, 0 ] ),
    entity( "&pfr;", [ 120109, 0 ] ),
    entity( "&phi;", [ 966, 0 ] ),
    entity( "&phiv;", [ 981, 0 ] ),
    entity( "&phmmat;", [ 8499, 0 ] ),
    entity( "&phone;", [ 9742, 0 ] ),
    entity( "&pi;", [ 960, 0 ] ),
    entity( "&pitchfork;", [ 8916, 0 ] ),
    entity( "&piv;", [ 982, 0 ] ),
    entity( "&planck;", [ 8463, 0 ] ),
    entity( "&planckh;", [ 8462, 0 ] ),
    entity( "&plankv;", [ 8463, 0 ] ),
    entity( "&plus;", [ 43, 0 ] ),
    entity( "&plusacir;", [ 10787, 0 ] ),
    entity( "&plusb;", [ 8862, 0 ] ),
    entity( "&pluscir;", [ 10786, 0 ] ),
    entity( "&plusdo;", [ 8724, 0 ] ),
    entity( "&plusdu;", [ 10789, 0 ] ),
    entity( "&pluse;", [ 10866, 0 ] ),
    entity( "&plusmn;", [ 177, 0 ] ),
    entity( "&plussim;", [ 10790, 0 ] ),
    entity( "&plustwo;", [ 10791, 0 ] ),
    entity( "&pm;", [ 177, 0 ] ),
    entity( "&pointint;", [ 10773, 0 ] ),
    entity( "&popf;", [ 120161, 0 ] ),
    entity( "&pound;", [ 163, 0 ] ),
    entity( "&pr;", [ 8826, 0 ] ),
    entity( "&prE;", [ 10931, 0 ] ),
    entity( "&prap;", [ 10935, 0 ] ),
    entity( "&prcue;", [ 8828, 0 ] ),
    entity( "&pre;", [ 10927, 0 ] ),
    entity( "&prec;", [ 8826, 0 ] ),
    entity( "&precapprox;", [ 10935, 0 ] ),
    entity( "&preccurlyeq;", [ 8828, 0 ] ),
    entity( "&preceq;", [ 10927, 0 ] ),
    entity( "&precnapprox;", [ 10937, 0 ] ),
    entity( "&precneqq;", [ 10933, 0 ] ),
    entity( "&precnsim;", [ 8936, 0 ] ),
    entity( "&precsim;", [ 8830, 0 ] ),
    entity( "&prime;", [ 8242, 0 ] ),
    entity( "&primes;", [ 8473, 0 ] ),
    entity( "&prnE;", [ 10933, 0 ] ),
    entity( "&prnap;", [ 10937, 0 ] ),
    entity( "&prnsim;", [ 8936, 0 ] ),
    entity( "&prod;", [ 8719, 0 ] ),
    entity( "&profalar;", [ 9006, 0 ] ),
    entity( "&profline;", [ 8978, 0 ] ),
    entity( "&profsurf;", [ 8979, 0 ] ),
    entity( "&prop;", [ 8733, 0 ] ),
    entity( "&propto;", [ 8733, 0 ] ),
    entity( "&prsim;", [ 8830, 0 ] ),
    entity( "&prurel;", [ 8880, 0 ] ),
    entity( "&pscr;", [ 120005, 0 ] ),
    entity( "&psi;", [ 968, 0 ] ),
    entity( "&puncsp;", [ 8200, 0 ] ),
    entity( "&qfr;", [ 120110, 0 ] ),
    entity( "&qint;", [ 10764, 0 ] ),
    entity( "&qopf;", [ 120162, 0 ] ),
    entity( "&qprime;", [ 8279, 0 ] ),
    entity( "&qscr;", [ 120006, 0 ] ),
    entity( "&quaternions;", [ 8461, 0 ] ),
    entity( "&quatint;", [ 10774, 0 ] ),
    entity( "&quest;", [ 63, 0 ] ),
    entity( "&questeq;", [ 8799, 0 ] ),
    entity( "&quot;", [ 34, 0 ] ),
    entity( "&rAarr;", [ 8667, 0 ] ),
    entity( "&rArr;", [ 8658, 0 ] ),
    entity( "&rAtail;", [ 10524, 0 ] ),
    entity( "&rBarr;", [ 10511, 0 ] ),
    entity( "&rHar;", [ 10596, 0 ] ),
    entity( "&race;", [ 8765, 817 ] ),
    entity( "&racute;", [ 341, 0 ] ),
    entity( "&radic;", [ 8730, 0 ] ),
    entity( "&raemptyv;", [ 10675, 0 ] ),
    entity( "&rang;", [ 10217, 0 ] ),
    entity( "&rangd;", [ 10642, 0 ] ),
    entity( "&range;", [ 10661, 0 ] ),
    entity( "&rangle;", [ 10217, 0 ] ),
    entity( "&raquo;", [ 187, 0 ] ),
    entity( "&rarr;", [ 8594, 0 ] ),
    entity( "&rarrap;", [ 10613, 0 ] ),
    entity( "&rarrb;", [ 8677, 0 ] ),
    entity( "&rarrbfs;", [ 10528, 0 ] ),
    entity( "&rarrc;", [ 10547, 0 ] ),
    entity( "&rarrfs;", [ 10526, 0 ] ),
    entity( "&rarrhk;", [ 8618, 0 ] ),
    entity( "&rarrlp;", [ 8620, 0 ] ),
    entity( "&rarrpl;", [ 10565, 0 ] ),
    entity( "&rarrsim;", [ 10612, 0 ] ),
    entity( "&rarrtl;", [ 8611, 0 ] ),
    entity( "&rarrw;", [ 8605, 0 ] ),
    entity( "&ratail;", [ 10522, 0 ] ),
    entity( "&ratio;", [ 8758, 0 ] ),
    entity( "&rationals;", [ 8474, 0 ] ),
    entity( "&rbarr;", [ 10509, 0 ] ),
    entity( "&rbbrk;", [ 10099, 0 ] ),
    entity( "&rbrace;", [ 125, 0 ] ),
    entity( "&rbrack;", [ 93, 0 ] ),
    entity( "&rbrke;", [ 10636, 0 ] ),
    entity( "&rbrksld;", [ 10638, 0 ] ),
    entity( "&rbrkslu;", [ 10640, 0 ] ),
    entity( "&rcaron;", [ 345, 0 ] ),
    entity( "&rcedil;", [ 343, 0 ] ),
    entity( "&rceil;", [ 8969, 0 ] ),
    entity( "&rcub;", [ 125, 0 ] ),
    entity( "&rcy;", [ 1088, 0 ] ),
    entity( "&rdca;", [ 10551, 0 ] ),
    entity( "&rdldhar;", [ 10601, 0 ] ),
    entity( "&rdquo;", [ 8221, 0 ] ),
    entity( "&rdquor;", [ 8221, 0 ] ),
    entity( "&rdsh;", [ 8627, 0 ] ),
    entity( "&real;", [ 8476, 0 ] ),
    entity( "&realine;", [ 8475, 0 ] ),
    entity( "&realpart;", [ 8476, 0 ] ),
    entity( "&reals;", [ 8477, 0 ] ),
    entity( "&rect;", [ 9645, 0 ] ),
    entity( "&reg;", [ 174, 0 ] ),
    entity( "&rfisht;", [ 10621, 0 ] ),
    entity( "&rfloor;", [ 8971, 0 ] ),
    entity( "&rfr;", [ 120111, 0 ] ),
    entity( "&rhard;", [ 8641, 0 ] ),
    entity( "&rharu;", [ 8640, 0 ] ),
    entity( "&rharul;", [ 10604, 0 ] ),
    entity( "&rho;", [ 961, 0 ] ),
    entity( "&rhov;", [ 1009, 0 ] ),
    entity( "&rightarrow;", [ 8594, 0 ] ),
    entity( "&rightarrowtail;", [ 8611, 0 ] ),
    entity( "&rightharpoondown;", [ 8641, 0 ] ),
    entity( "&rightharpoonup;", [ 8640, 0 ] ),
    entity( "&rightleftarrows;", [ 8644, 0 ] ),
    entity( "&rightleftharpoons;", [ 8652, 0 ] ),
    entity( "&rightrightarrows;", [ 8649, 0 ] ),
    entity( "&rightsquigarrow;", [ 8605, 0 ] ),
    entity( "&rightthreetimes;", [ 8908, 0 ] ),
    entity( "&ring;", [ 730, 0 ] ),
    entity( "&risingdotseq;", [ 8787, 0 ] ),
    entity( "&rlarr;", [ 8644, 0 ] ),
    entity( "&rlhar;", [ 8652, 0 ] ),
    entity( "&rlm;", [ 8207, 0 ] ),
    entity( "&rmoust;", [ 9137, 0 ] ),
    entity( "&rmoustache;", [ 9137, 0 ] ),
    entity( "&rnmid;", [ 10990, 0 ] ),
    entity( "&roang;", [ 10221, 0 ] ),
    entity( "&roarr;", [ 8702, 0 ] ),
    entity( "&robrk;", [ 10215, 0 ] ),
    entity( "&ropar;", [ 10630, 0 ] ),
    entity( "&ropf;", [ 120163, 0 ] ),
    entity( "&roplus;", [ 10798, 0 ] ),
    entity( "&rotimes;", [ 10805, 0 ] ),
    entity( "&rpar;", [ 41, 0 ] ),
    entity( "&rpargt;", [ 10644, 0 ] ),
    entity( "&rppolint;", [ 10770, 0 ] ),
    entity( "&rrarr;", [ 8649, 0 ] ),
    entity( "&rsaquo;", [ 8250, 0 ] ),
    entity( "&rscr;", [ 120007, 0 ] ),
    entity( "&rsh;", [ 8625, 0 ] ),
    entity( "&rsqb;", [ 93, 0 ] ),
    entity( "&rsquo;", [ 8217, 0 ] ),
    entity( "&rsquor;", [ 8217, 0 ] ),
    entity( "&rthree;", [ 8908, 0 ] ),
    entity( "&rtimes;", [ 8906, 0 ] ),
    entity( "&rtri;", [ 9657, 0 ] ),
    entity( "&rtrie;", [ 8885, 0 ] ),
    entity( "&rtrif;", [ 9656, 0 ] ),
    entity( "&rtriltri;", [ 10702, 0 ] ),
    entity( "&ruluhar;", [ 10600, 0 ] ),
    entity( "&rx;", [ 8478, 0 ] ),
    entity( "&sacute;", [ 347, 0 ] ),
    entity( "&sbquo;", [ 8218, 0 ] ),
    entity( "&sc;", [ 8827, 0 ] ),
    entity( "&scE;", [ 10932, 0 ] ),
    entity( "&scap;", [ 10936, 0 ] ),
    entity( "&scaron;", [ 353, 0 ] ),
    entity( "&sccue;", [ 8829, 0 ] ),
    entity( "&sce;", [ 10928, 0 ] ),
    entity( "&scedil;", [ 351, 0 ] ),
    entity( "&scirc;", [ 349, 0 ] ),
    entity( "&scnE;", [ 10934, 0 ] ),
    entity( "&scnap;", [ 10938, 0 ] ),
    entity( "&scnsim;", [ 8937, 0 ] ),
    entity( "&scpolint;", [ 10771, 0 ] ),
    entity( "&scsim;", [ 8831, 0 ] ),
    entity( "&scy;", [ 1089, 0 ] ),
    entity( "&sdot;", [ 8901, 0 ] ),
    entity( "&sdotb;", [ 8865, 0 ] ),
    entity( "&sdote;", [ 10854, 0 ] ),
    entity( "&seArr;", [ 8664, 0 ] ),
    entity( "&searhk;", [ 10533, 0 ] ),
    entity( "&searr;", [ 8600, 0 ] ),
    entity( "&searrow;", [ 8600, 0 ] ),
    entity( "&sect;", [ 167, 0 ] ),
    entity( "&semi;", [ 59, 0 ] ),
    entity( "&seswar;", [ 10537, 0 ] ),
    entity( "&setminus;", [ 8726, 0 ] ),
    entity( "&setmn;", [ 8726, 0 ] ),
    entity( "&sext;", [ 10038, 0 ] ),
    entity( "&sfr;", [ 120112, 0 ] ),
    entity( "&sfrown;", [ 8994, 0 ] ),
    entity( "&sharp;", [ 9839, 0 ] ),
    entity( "&shchcy;", [ 1097, 0 ] ),
    entity( "&shcy;", [ 1096, 0 ] ),
    entity( "&shortmid;", [ 8739, 0 ] ),
    entity( "&shortparallel;", [ 8741, 0 ] ),
    entity( "&shy;", [ 173, 0 ] ),
    entity( "&sigma;", [ 963, 0 ] ),
    entity( "&sigmaf;", [ 962, 0 ] ),
    entity( "&sigmav;", [ 962, 0 ] ),
    entity( "&sim;", [ 8764, 0 ] ),
    entity( "&simdot;", [ 10858, 0 ] ),
    entity( "&sime;", [ 8771, 0 ] ),
    entity( "&simeq;", [ 8771, 0 ] ),
    entity( "&simg;", [ 10910, 0 ] ),
    entity( "&simgE;", [ 10912, 0 ] ),
    entity( "&siml;", [ 10909, 0 ] ),
    entity( "&simlE;", [ 10911, 0 ] ),
    entity( "&simne;", [ 8774, 0 ] ),
    entity( "&simplus;", [ 10788, 0 ] ),
    entity( "&simrarr;", [ 10610, 0 ] ),
    entity( "&slarr;", [ 8592, 0 ] ),
    entity( "&smallsetminus;", [ 8726, 0 ] ),
    entity( "&smashp;", [ 10803, 0 ] ),
    entity( "&smeparsl;", [ 10724, 0 ] ),
    entity( "&smid;", [ 8739, 0 ] ),
    entity( "&smile;", [ 8995, 0 ] ),
    entity( "&smt;", [ 10922, 0 ] ),
    entity( "&smte;", [ 10924, 0 ] ),
    entity( "&smtes;", [ 10924, 65024 ] ),
    entity( "&softcy;", [ 1100, 0 ] ),
    entity( "&sol;", [ 47, 0 ] ),
    entity( "&solb;", [ 10692, 0 ] ),
    entity( "&solbar;", [ 9023, 0 ] ),
    entity( "&sopf;", [ 120164, 0 ] ),
    entity( "&spades;", [ 9824, 0 ] ),
    entity( "&spadesuit;", [ 9824, 0 ] ),
    entity( "&spar;", [ 8741, 0 ] ),
    entity( "&sqcap;", [ 8851, 0 ] ),
    entity( "&sqcaps;", [ 8851, 65024 ] ),
    entity( "&sqcup;", [ 8852, 0 ] ),
    entity( "&sqcups;", [ 8852, 65024 ] ),
    entity( "&sqsub;", [ 8847, 0 ] ),
    entity( "&sqsube;", [ 8849, 0 ] ),
    entity( "&sqsubset;", [ 8847, 0 ] ),
    entity( "&sqsubseteq;", [ 8849, 0 ] ),
    entity( "&sqsup;", [ 8848, 0 ] ),
    entity( "&sqsupe;", [ 8850, 0 ] ),
    entity( "&sqsupset;", [ 8848, 0 ] ),
    entity( "&sqsupseteq;", [ 8850, 0 ] ),
    entity( "&squ;", [ 9633, 0 ] ),
    entity( "&square;", [ 9633, 0 ] ),
    entity( "&squarf;", [ 9642, 0 ] ),
    entity( "&squf;", [ 9642, 0 ] ),
    entity( "&srarr;", [ 8594, 0 ] ),
    entity( "&sscr;", [ 120008, 0 ] ),
    entity( "&ssetmn;", [ 8726, 0 ] ),
    entity( "&ssmile;", [ 8995, 0 ] ),
    entity( "&sstarf;", [ 8902, 0 ] ),
    entity( "&star;", [ 9734, 0 ] ),
    entity( "&starf;", [ 9733, 0 ] ),
    entity( "&straightepsilon;", [ 1013, 0 ] ),
    entity( "&straightphi;", [ 981, 0 ] ),
    entity( "&strns;", [ 175, 0 ] ),
    entity( "&sub;", [ 8834, 0 ] ),
    entity( "&subE;", [ 10949, 0 ] ),
    entity( "&subdot;", [ 10941, 0 ] ),
    entity( "&sube;", [ 8838, 0 ] ),
    entity( "&subedot;", [ 10947, 0 ] ),
    entity( "&submult;", [ 10945, 0 ] ),
    entity( "&subnE;", [ 10955, 0 ] ),
    entity( "&subne;", [ 8842, 0 ] ),
    entity( "&subplus;", [ 10943, 0 ] ),
    entity( "&subrarr;", [ 10617, 0 ] ),
    entity( "&subset;", [ 8834, 0 ] ),
    entity( "&subseteq;", [ 8838, 0 ] ),
    entity( "&subseteqq;", [ 10949, 0 ] ),
    entity( "&subsetneq;", [ 8842, 0 ] ),
    entity( "&subsetneqq;", [ 10955, 0 ] ),
    entity( "&subsim;", [ 10951, 0 ] ),
    entity( "&subsub;", [ 10965, 0 ] ),
    entity( "&subsup;", [ 10963, 0 ] ),
    entity( "&succ;", [ 8827, 0 ] ),
    entity( "&succapprox;", [ 10936, 0 ] ),
    entity( "&succcurlyeq;", [ 8829, 0 ] ),
    entity( "&succeq;", [ 10928, 0 ] ),
    entity( "&succnapprox;", [ 10938, 0 ] ),
    entity( "&succneqq;", [ 10934, 0 ] ),
    entity( "&succnsim;", [ 8937, 0 ] ),
    entity( "&succsim;", [ 8831, 0 ] ),
    entity( "&sum;", [ 8721, 0 ] ),
    entity( "&sung;", [ 9834, 0 ] ),
    entity( "&sup1",  [185, 0 ] ),
    entity( "&sup1;", [ 185, 0 ] ),
    entity( "&sup2",  [178, 0 ] ),
    entity( "&sup2;", [ 178, 0 ] ),
    entity( "&sup3",  [179, 0 ] ),
    entity( "&sup3;", [ 179, 0 ] ),
    entity( "&sup;", [ 8835, 0 ] ),
    entity( "&supE;", [ 10950, 0 ] ),
    entity( "&supdot;", [ 10942, 0 ] ),
    entity( "&supdsub;", [ 10968, 0 ] ),
    entity( "&supe;", [ 8839, 0 ] ),
    entity( "&supedot;", [ 10948, 0 ] ),
    entity( "&suphsol;", [ 10185, 0 ] ),
    entity( "&suphsub;", [ 10967, 0 ] ),
    entity( "&suplarr;", [ 10619, 0 ] ),
    entity( "&supmult;", [ 10946, 0 ] ),
    entity( "&supnE;", [ 10956, 0 ] ),
    entity( "&supne;", [ 8843, 0 ] ),
    entity( "&supplus;", [ 10944, 0 ] ),
    entity( "&supset;", [ 8835, 0 ] ),
    entity( "&supseteq;", [ 8839, 0 ] ),
    entity( "&supseteqq;", [ 10950, 0 ] ),
    entity( "&supsetneq;", [ 8843, 0 ] ),
    entity( "&supsetneqq;", [ 10956, 0 ] ),
    entity( "&supsim;", [ 10952, 0 ] ),
    entity( "&supsub;", [ 10964, 0 ] ),
    entity( "&supsup;", [ 10966, 0 ] ),
    entity( "&swArr;", [ 8665, 0 ] ),
    entity( "&swarhk;", [ 10534, 0 ] ),
    entity( "&swarr;", [ 8601, 0 ] ),
    entity( "&swarrow;", [ 8601, 0 ] ),
    entity( "&swnwar;", [ 10538, 0 ] ),
    entity( "&szlig;", [ 223, 0 ] ),
    entity( "&target;", [ 8982, 0 ] ),
    entity( "&tau;", [ 964, 0 ] ),
    entity( "&tbrk;", [ 9140, 0 ] ),
    entity( "&tcaron;", [ 357, 0 ] ),
    entity( "&tcedil;", [ 355, 0 ] ),
    entity( "&tcy;", [ 1090, 0 ] ),
    entity( "&tdot;", [ 8411, 0 ] ),
    entity( "&telrec;", [ 8981, 0 ] ),
    entity( "&tfr;", [ 120113, 0 ] ),
    entity( "&there4;", [ 8756, 0 ] ),
    entity( "&therefore;", [ 8756, 0 ] ),
    entity( "&theta;", [ 952, 0 ] ),
    entity( "&thetasym;", [ 977, 0 ] ),
    entity( "&thetav;", [ 977, 0 ] ),
    entity( "&thickapprox;", [ 8776, 0 ] ),
    entity( "&thicksim;", [ 8764, 0 ] ),
    entity( "&thinsp;", [ 8201, 0 ] ),
    entity( "&thkap;", [ 8776, 0 ] ),
    entity( "&thksim;", [ 8764, 0 ] ),
    entity( "&thorn;", [ 254, 0 ] ),
    entity( "&tilde;", [ 732, 0 ] ),
    entity( "&times;", [ 215, 0 ] ),
    entity( "&timesb;", [ 8864, 0 ] ),
    entity( "&timesbar;", [ 10801, 0 ] ),
    entity( "&timesd;", [ 10800, 0 ] ),
    entity( "&tint;", [ 8749, 0 ] ),
    entity( "&toea;", [ 10536, 0 ] ),
    entity( "&top;", [ 8868, 0 ] ),
    entity( "&topbot;", [ 9014, 0 ] ),
    entity( "&topcir;", [ 10993, 0 ] ),
    entity( "&topf;", [ 120165, 0 ] ),
    entity( "&topfork;", [ 10970, 0 ] ),
    entity( "&tosa;", [ 10537, 0 ] ),
    entity( "&tprime;", [ 8244, 0 ] ),
    entity( "&trade;", [ 8482, 0 ] ),
    entity( "&triangle;", [ 9653, 0 ] ),
    entity( "&triangledown;", [ 9663, 0 ] ),
    entity( "&triangleleft;", [ 9667, 0 ] ),
    entity( "&trianglelefteq;", [ 8884, 0 ] ),
    entity( "&triangleq;", [ 8796, 0 ] ),
    entity( "&triangleright;", [ 9657, 0 ] ),
    entity( "&trianglerighteq;", [ 8885, 0 ] ),
    entity( "&tridot;", [ 9708, 0 ] ),
    entity( "&trie;", [ 8796, 0 ] ),
    entity( "&triminus;", [ 10810, 0 ] ),
    entity( "&triplus;", [ 10809, 0 ] ),
    entity( "&trisb;", [ 10701, 0 ] ),
    entity( "&tritime;", [ 10811, 0 ] ),
    entity( "&trpezium;", [ 9186, 0 ] ),
    entity( "&tscr;", [ 120009, 0 ] ),
    entity( "&tscy;", [ 1094, 0 ] ),
    entity( "&tshcy;", [ 1115, 0 ] ),
    entity( "&tstrok;", [ 359, 0 ] ),
    entity( "&twixt;", [ 8812, 0 ] ),
    entity( "&twoheadleftarrow;", [ 8606, 0 ] ),
    entity( "&twoheadrightarrow;", [ 8608, 0 ] ),
    entity( "&uArr;", [ 8657, 0 ] ),
    entity( "&uHar;", [ 10595, 0 ] ),
    entity( "&uacute;", [ 250, 0 ] ),
    entity( "&uarr;", [ 8593, 0 ] ),
    entity( "&ubrcy;", [ 1118, 0 ] ),
    entity( "&ubreve;", [ 365, 0 ] ),
    entity( "&ucirc;", [ 251, 0 ] ),
    entity( "&ucy;", [ 1091, 0 ] ),
    entity( "&udarr;", [ 8645, 0 ] ),
    entity( "&udblac;", [ 369, 0 ] ),
    entity( "&udhar;", [ 10606, 0 ] ),
    entity( "&ufisht;", [ 10622, 0 ] ),
    entity( "&ufr;", [ 120114, 0 ] ),
    entity( "&ugrave;", [ 249, 0 ] ),
    entity( "&uharl;", [ 8639, 0 ] ),
    entity( "&uharr;", [ 8638, 0 ] ),
    entity( "&uhblk;", [ 9600, 0 ] ),
    entity( "&ulcorn;", [ 8988, 0 ] ),
    entity( "&ulcorner;", [ 8988, 0 ] ),
    entity( "&ulcrop;", [ 8975, 0 ] ),
    entity( "&ultri;", [ 9720, 0 ] ),
    entity( "&umacr;", [ 363, 0 ] ),
    entity( "&uml;", [ 168, 0 ] ),
    entity( "&uogon;", [ 371, 0 ] ),
    entity( "&uopf;", [ 120166, 0 ] ),
    entity( "&uparrow;", [ 8593, 0 ] ),
    entity( "&updownarrow;", [ 8597, 0 ] ),
    entity( "&upharpoonleft;", [ 8639, 0 ] ),
    entity( "&upharpoonright;", [ 8638, 0 ] ),
    entity( "&uplus;", [ 8846, 0 ] ),
    entity( "&upsi;", [ 965, 0 ] ),
    entity( "&upsih;", [ 978, 0 ] ),
    entity( "&upsilon;", [ 965, 0 ] ),
    entity( "&upuparrows;", [ 8648, 0 ] ),
    entity( "&urcorn;", [ 8989, 0 ] ),
    entity( "&urcorner;", [ 8989, 0 ] ),
    entity( "&urcrop;", [ 8974, 0 ] ),
    entity( "&uring;", [ 367, 0 ] ),
    entity( "&urtri;", [ 9721, 0 ] ),
    entity( "&uscr;", [ 120010, 0 ] ),
    entity( "&utdot;", [ 8944, 0 ] ),
    entity( "&utilde;", [ 361, 0 ] ),
    entity( "&utri;", [ 9653, 0 ] ),
    entity( "&utrif;", [ 9652, 0 ] ),
    entity( "&uuarr;", [ 8648, 0 ] ),
    entity( "&uuml;", [ 252, 0 ] ),
    entity( "&uwangle;", [ 10663, 0 ] ),
    entity( "&vArr;", [ 8661, 0 ] ),
    entity( "&vBar;", [ 10984, 0 ] ),
    entity( "&vBarv;", [ 10985, 0 ] ),
    entity( "&vDash;", [ 8872, 0 ] ),
    entity( "&vangrt;", [ 10652, 0 ] ),
    entity( "&varepsilon;", [ 1013, 0 ] ),
    entity( "&varkappa;", [ 1008, 0 ] ),
    entity( "&varnothing;", [ 8709, 0 ] ),
    entity( "&varphi;", [ 981, 0 ] ),
    entity( "&varpi;", [ 982, 0 ] ),
    entity( "&varpropto;", [ 8733, 0 ] ),
    entity( "&varr;", [ 8597, 0 ] ),
    entity( "&varrho;", [ 1009, 0 ] ),
    entity( "&varsigma;", [ 962, 0 ] ),
    entity( "&varsubsetneq;", [ 8842, 65024 ] ),
    entity( "&varsubsetneqq;", [ 10955, 65024 ] ),
    entity( "&varsupsetneq;", [ 8843, 65024 ] ),
    entity( "&varsupsetneqq;", [ 10956, 65024 ] ),
    entity( "&vartheta;", [ 977, 0 ] ),
    entity( "&vartriangleleft;", [ 8882, 0 ] ),
    entity( "&vartriangleright;", [ 8883, 0 ] ),
    entity( "&vcy;", [ 1074, 0 ] ),
    entity( "&vdash;", [ 8866, 0 ] ),
    entity( "&vee;", [ 8744, 0 ] ),
    entity( "&veebar;", [ 8891, 0 ] ),
    entity( "&veeeq;", [ 8794, 0 ] ),
    entity( "&vellip;", [ 8942, 0 ] ),
    entity( "&verbar;", [ 124, 0 ] ),
    entity( "&vert;", [ 124, 0 ] ),
    entity( "&vfr;", [ 120115, 0 ] ),
    entity( "&vltri;", [ 8882, 0 ] ),
    entity( "&vnsub;", [ 8834, 8402 ] ),
    entity( "&vnsup;", [ 8835, 8402 ] ),
    entity( "&vopf;", [ 120167, 0 ] ),
    entity( "&vprop;", [ 8733, 0 ] ),
    entity( "&vrtri;", [ 8883, 0 ] ),
    entity( "&vscr;", [ 120011, 0 ] ),
    entity( "&vsubnE;", [ 10955, 65024 ] ),
    entity( "&vsubne;", [ 8842, 65024 ] ),
    entity( "&vsupnE;", [ 10956, 65024 ] ),
    entity( "&vsupne;", [ 8843, 65024 ] ),
    entity( "&vzigzag;", [ 10650, 0 ] ),
    entity( "&wcirc;", [ 373, 0 ] ),
    entity( "&wedbar;", [ 10847, 0 ] ),
    entity( "&wedge;", [ 8743, 0 ] ),
    entity( "&wedgeq;", [ 8793, 0 ] ),
    entity( "&weierp;", [ 8472, 0 ] ),
    entity( "&wfr;", [ 120116, 0 ] ),
    entity( "&wopf;", [ 120168, 0 ] ),
    entity( "&wp;", [ 8472, 0 ] ),
    entity( "&wr;", [ 8768, 0 ] ),
    entity( "&wreath;", [ 8768, 0 ] ),
    entity( "&wscr;", [ 120012, 0 ] ),
    entity( "&xcap;", [ 8898, 0 ] ),
    entity( "&xcirc;", [ 9711, 0 ] ),
    entity( "&xcup;", [ 8899, 0 ] ),
    entity( "&xdtri;", [ 9661, 0 ] ),
    entity( "&xfr;", [ 120117, 0 ] ),
    entity( "&xhArr;", [ 10234, 0 ] ),
    entity( "&xharr;", [ 10231, 0 ] ),
    entity( "&xi;", [ 958, 0 ] ),
    entity( "&xlArr;", [ 10232, 0 ] ),
    entity( "&xlarr;", [ 10229, 0 ] ),
    entity( "&xmap;", [ 10236, 0 ] ),
    entity( "&xnis;", [ 8955, 0 ] ),
    entity( "&xodot;", [ 10752, 0 ] ),
    entity( "&xopf;", [ 120169, 0 ] ),
    entity( "&xoplus;", [ 10753, 0 ] ),
    entity( "&xotime;", [ 10754, 0 ] ),
    entity( "&xrArr;", [ 10233, 0 ] ),
    entity( "&xrarr;", [ 10230, 0 ] ),
    entity( "&xscr;", [ 120013, 0 ] ),
    entity( "&xsqcup;", [ 10758, 0 ] ),
    entity( "&xuplus;", [ 10756, 0 ] ),
    entity( "&xutri;", [ 9651, 0 ] ),
    entity( "&xvee;", [ 8897, 0 ] ),
    entity( "&xwedge;", [ 8896, 0 ] ),
    entity( "&yacute;", [ 253, 0 ] ),
    entity( "&yacy;", [ 1103, 0 ] ),
    entity( "&ycirc;", [ 375, 0 ] ),
    entity( "&ycy;", [ 1099, 0 ] ),
    entity( "&yen;", [ 165, 0 ] ),
    entity( "&yfr;", [ 120118, 0 ] ),
    entity( "&yicy;", [ 1111, 0 ] ),
    entity( "&yopf;", [ 120170, 0 ] ),
    entity( "&yscr;", [ 120014, 0 ] ),
    entity( "&yucy;", [ 1102, 0 ] ),
    entity( "&yuml;", [ 255, 0 ] ),
    entity( "&zacute;", [ 378, 0 ] ),
    entity( "&zcaron;", [ 382, 0 ] ),
    entity( "&zcy;", [ 1079, 0 ] ),
    entity( "&zdot;", [ 380, 0 ] ),
    entity( "&zeetrf;", [ 8488, 0 ] ),
    entity( "&zeta;", [ 950, 0 ] ),
    entity( "&zfr;", [ 120119, 0 ] ),
    entity( "&zhcy;", [ 1078, 0 ] ),
    entity( "&zigrarr;", [ 8669, 0 ] ),
    entity( "&zopf;", [ 120171, 0 ] ),
    entity( "&zscr;", [ 120015, 0 ] ),
    entity( "&zwj;", [ 8205, 0 ] ),
    entity( "&zwnj;", [ 8204, 0 ] ),
];


struct entity_key
{
    const(char)* name;
    size_t name_size;
}

extern(C) int entity_cmp(scope const(void)* p_key, scope const(void)* p_entity)
{
    entity_key* key = cast(entity_key*) p_key;
    entity* ent = cast(entity*) p_entity;
    return strncmp(key.name, ent.name, key.name_size);
}

const(entity)* entity_lookup(const(char)* name, size_t name_size)
{
    entity_key key = entity_key(name, name_size);
    const(void)* result = bsearch(&key, cast(const(void)*)entity_table.ptr, entity_table.length, entity.sizeof, &entity_cmp);
    return cast(const(entity)*)result;
}

//
// HTML RENDERING
//

/* If set, debug output from md_parse() is sent to stderr. */
enum MD_RENDER_FLAG_DEBUG = 0x0001;

enum MD_RENDER_FLAG_VERBATIM_ENTITIES = 0x0002;


struct MD_RENDER_HTML
{
    void function(const(MD_CHAR)*, MD_SIZE, void*) nothrow @nogc process_output;
    void* userdata;
    uint flags;
    int image_nesting_level;
    char[256] escape_map;
}


/*****************************************
 ***  HTML rendering helper functions  ***
 *****************************************/

/*
#define ISDIGIT(ch)
#define ISLOWER(ch)
#define ISUPPER(ch)
*/
bool ISALNUM_HTML(CHAR ch)
{
    return ('a' <= ch && ch <= 'z') || ('A' <= ch && ch <= 'Z') || ('0' <= ch && ch <= '9');
}

void render_text(MD_RENDER_HTML* r, const(MD_CHAR)* text, MD_SIZE size)
{
    r.process_output(text, size, r.userdata);
}

void RENDER_LITERAL(MD_RENDER_HTML* r, const(MD_CHAR)* literal)
{
    render_text(r, literal, cast(uint) strlen(literal));
}

/* Some characters need to be escaped in normal HTML text. */
bool HTML_NEED_ESCAPE(MD_RENDER_HTML* r, CHAR ch)
{
    return (r.escape_map[cast(ubyte)(ch)] != 0);
}

void render_html_escaped(MD_RENDER_HTML* r, const MD_CHAR* data, MD_SIZE size)
{
    MD_OFFSET beg = 0;
    MD_OFFSET off = 0;

    while(1) {
        /* Optimization: Use some loop unrolling. */
        while(off + 3 < size  &&  !HTML_NEED_ESCAPE(r, data[off+0])  &&  !HTML_NEED_ESCAPE(r, data[off+1])
                              &&  !HTML_NEED_ESCAPE(r, data[off+2])  &&  !HTML_NEED_ESCAPE(r, data[off+3]))
            off += 4;
        while(off < size  &&  !HTML_NEED_ESCAPE(r, data[off]))
            off++;

        if(off > beg)
            render_text(r, data + beg, off - beg);

        if(off < size) {
            switch(data[off]) {
                case '&':   RENDER_LITERAL(r, "&amp;"); break;
                case '<':   RENDER_LITERAL(r, "&lt;"); break;
                case '>':   RENDER_LITERAL(r, "&gt;"); break;
                case '"':   RENDER_LITERAL(r, "&quot;"); break;
                default: break;
            }
            off++;
        } else {
            break;
        }
        beg = off;
    }
}


bool URL_NEED_ESCAPE(CHAR ch)
{
    return (!ISALNUM_HTML(ch) && strchr("-_.+!*'(),%#@?=;:/,+$", ch) == null);
}

void render_url_escaped(MD_RENDER_HTML* r, const MD_CHAR* data, MD_SIZE size)
{
    static immutable(MD_CHAR)[] hex_chars = "0123456789ABCDEF";
    MD_OFFSET beg = 0;
    MD_OFFSET off = 0;

    while(1) {
        while(off < size  &&  !URL_NEED_ESCAPE(data[off]))
            off++;
        if(off > beg)
            render_text(r, data + beg, off - beg);

        if(off < size) {
            char[3] hex;

            switch(data[off]) {
                case '&':   RENDER_LITERAL(r, "&amp;"); break;
                case '\'':  RENDER_LITERAL(r, "&#x27;"); break;
                default:
                    hex[0] = '%';
                    hex[1] = hex_chars[(cast(uint)data[off] >> 4) & 0xf];
                    hex[2] = hex_chars[(cast(uint)data[off] >> 0) & 0xf];
                    render_text(r, hex.ptr, 3);
                    break;
            }
            off++;
        } else {
            break;
        }

        beg = off;
    }
}

uint hex_val(char ch)
{
    if('0' <= ch && ch <= '9')
        return ch - '0';
    if('A' <= ch && ch <= 'Z')
        return ch - 'A' + 10;
    else
        return ch - 'a' + 10;
}

alias appendFunc = nothrow @nogc void function(MD_RENDER_HTML*, const(MD_CHAR)*, MD_SIZE);

void render_utf8_codepoint(MD_RENDER_HTML* r, uint codepoint,
                           appendFunc fn_append)
{
    static immutable(MD_CHAR)[] utf8_replacement_char = [ 0xef, 0xbf, 0xbd ];

    char[4] utf8;
    size_t n;

    if(codepoint <= 0x7f) {
        n = 1;
        utf8[0] = cast(ubyte) codepoint;
    } else if(codepoint <= 0x7ff) {
        n = 2;
        utf8[0] = 0xc0 | ((codepoint >>  6) & 0x1f);
        utf8[1] = 0x80 + ((codepoint >>  0) & 0x3f);
    } else if(codepoint <= 0xffff) {
        n = 3;
        utf8[0] = 0xe0 | ((codepoint >> 12) & 0xf);
        utf8[1] = 0x80 + ((codepoint >>  6) & 0x3f);
        utf8[2] = 0x80 + ((codepoint >>  0) & 0x3f);
    } else {
        n = 4;
        utf8[0] = 0xf0 | ((codepoint >> 18) & 0x7);
        utf8[1] = 0x80 + ((codepoint >> 12) & 0x3f);
        utf8[2] = 0x80 + ((codepoint >>  6) & 0x3f);
        utf8[3] = 0x80 + ((codepoint >>  0) & 0x3f);
    }

    if(0 < codepoint  &&  codepoint <= 0x10ffff)
        fn_append(r, utf8.ptr, cast(uint)n);
    else
        fn_append(r, utf8_replacement_char.ptr, 3);
}

/* Translate entity to its UTF-8 equivalent, or output the verbatim one
 * if such entity is unknown (or if the translation is disabled). */
void render_entity(MD_RENDER_HTML* r, const(MD_CHAR)* text, MD_SIZE size,
                   appendFunc fn_append)
{
    if(r.flags & MD_RENDER_FLAG_VERBATIM_ENTITIES) {
        fn_append(r, text, size);
        return;
    }

    /* We assume UTF-8 output is what is desired. */
    if(size > 3 && text[1] == '#') {
        uint codepoint = 0;

        if(text[2] == 'x' || text[2] == 'X') {
            /* Hexadecimal entity (e.g. "&#x1234abcd;")). */
            MD_SIZE i;
            for(i = 3; i < size-1; i++)
                codepoint = 16 * codepoint + hex_val(text[i]);
        } else {
            /* Decimal entity (e.g. "&1234;") */
            MD_SIZE i;
            for(i = 2; i < size-1; i++)
                codepoint = 10 * codepoint + (text[i] - '0');
        }

        render_utf8_codepoint(r, codepoint, fn_append);
        return;
    } else {
        /* Named entity (e.g. "&nbsp;"). */
        const(entity)* ent;

        ent = entity_lookup(text, size);
        if(ent != null) {
            render_utf8_codepoint(r, ent.codepoints[0], fn_append);
            if(ent.codepoints[1])
                render_utf8_codepoint(r, ent.codepoints[1], fn_append);
            return;
        }
    }

    fn_append(r, text, size);
}

void render_attribute(MD_RENDER_HTML* r, const MD_ATTRIBUTE* attr,
                      appendFunc fn_append)
{
    int i;

    for(i = 0; attr.substr_offsets[i] < attr.size; i++) {
        MD_TEXTTYPE type = attr.substr_types[i];
        MD_OFFSET off = attr.substr_offsets[i];
        MD_SIZE size = attr.substr_offsets[i+1] - off;
        const MD_CHAR* text = attr.text + off;

        switch(type) {
            case MD_TEXT_NULLCHAR:  render_utf8_codepoint(r, 0x0000, &render_text); break;
            case MD_TEXT_ENTITY:    render_entity(r, text, size, fn_append); break;
            default:                fn_append(r, text, size); break;
        }
    }
}


void render_open_ol_block(MD_RENDER_HTML* r, const(MD_BLOCK_OL_DETAIL)* det)
{
    char[64] buf;

    if(det.start == 1) {
        RENDER_LITERAL(r, "<ol>\n");
        return;
    }

    snprintf(buf.ptr, buf.length, "<ol start=\"%u\">\n", det.start);
    RENDER_LITERAL(r, buf.ptr);
}

void render_open_li_block(MD_RENDER_HTML* r, const(MD_BLOCK_LI_DETAIL)* det)
{
    if(det.is_task) {
        RENDER_LITERAL(r, "<li class=\"task-list-item\">" ~
                          "<input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled");
        if(det.task_mark == 'x' || det.task_mark == 'X')
            RENDER_LITERAL(r, " checked");
        RENDER_LITERAL(r, ">");
    } else {
        RENDER_LITERAL(r, "<li>");
    }
}

void render_open_code_block(MD_RENDER_HTML* r, const(MD_BLOCK_CODE_DETAIL)* det)
{
    RENDER_LITERAL(r, "<pre><code");

    /* If known, output the HTML 5 attribute class="language-LANGNAME". */
    if(det.lang.text != null) {
        RENDER_LITERAL(r, " class=\"language-");
        render_attribute(r, &det.lang, &render_html_escaped);
        RENDER_LITERAL(r, "\"");
    }

    RENDER_LITERAL(r, ">");
}

void render_open_td_block(MD_RENDER_HTML* r, const(MD_CHAR)* cell_type, const(MD_BLOCK_TD_DETAIL)* det)
{
    RENDER_LITERAL(r, "<");
    RENDER_LITERAL(r, cell_type);

    switch(det.align_)
    {
        case MD_ALIGN_LEFT:     RENDER_LITERAL(r, " align=\"left\">"); break;
        case MD_ALIGN_CENTER:   RENDER_LITERAL(r, " align=\"center\">"); break;
        case MD_ALIGN_RIGHT:    RENDER_LITERAL(r, " align=\"right\">"); break;
        default:                RENDER_LITERAL(r, ">"); break;
    }
}

void render_open_a_span(MD_RENDER_HTML* r, const(MD_SPAN_A_DETAIL)* det)
{
    RENDER_LITERAL(r, "<a href=\"");
    render_attribute(r, &det.href, &render_url_escaped);

    if(det.title.text != null) {
        RENDER_LITERAL(r, "\" title=\"");
        render_attribute(r, &det.title, &render_html_escaped);
    }

    RENDER_LITERAL(r, "\">");
}

void render_open_img_span(MD_RENDER_HTML* r, const(MD_SPAN_IMG_DETAIL)* det)
{
    RENDER_LITERAL(r, "<img src=\"");
    render_attribute(r, &det.src, &render_url_escaped);

    RENDER_LITERAL(r, "\" alt=\"");

    r.image_nesting_level++;
}

void render_close_img_span(MD_RENDER_HTML* r, const(MD_SPAN_IMG_DETAIL)* det)
{
    if(det.title.text != null) {
        RENDER_LITERAL(r, "\" title=\"");
        render_attribute(r, &det.title, &render_html_escaped);
    }
    RENDER_LITERAL(r, "\" />");
    r.image_nesting_level--;
}


/**************************************
 ***  HTML renderer implementation  ***
 **************************************/

int enter_block_callback(MD_BLOCKTYPE type, void* detail, void* userdata)
{
    static immutable(MD_CHAR)*[6] head = [ "<h1>", "<h2>", "<h3>", "<h4>", "<h5>", "<h6>" ];
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;

    switch(type)
    {
        case MD_BLOCK_DOC:      /* noop */ break;
        case MD_BLOCK_QUOTE:    RENDER_LITERAL(r, "<blockquote>\n"); break;
        case MD_BLOCK_UL:       RENDER_LITERAL(r, "<ul>\n"); break;
        case MD_BLOCK_OL:       render_open_ol_block(r, cast(const(MD_BLOCK_OL_DETAIL)*)detail); break;
        case MD_BLOCK_LI:       render_open_li_block(r, cast(const(MD_BLOCK_LI_DETAIL)*)detail); break;
        case MD_BLOCK_HR:       RENDER_LITERAL(r, "<hr />\n"); break;
        case MD_BLOCK_H:        RENDER_LITERAL(r, head[(cast(MD_BLOCK_H_DETAIL*)detail).level - 1]); break;
        case MD_BLOCK_CODE:     render_open_code_block(r, cast(const(MD_BLOCK_CODE_DETAIL)*) detail); break;
        case MD_BLOCK_HTML:     /* noop */ break;
        case MD_BLOCK_P:        RENDER_LITERAL(r, "<p>"); break;
        case MD_BLOCK_TABLE:    RENDER_LITERAL(r, "<table>\n"); break;
        case MD_BLOCK_THEAD:    RENDER_LITERAL(r, "<thead>\n"); break;
        case MD_BLOCK_TBODY:    RENDER_LITERAL(r, "<tbody>\n"); break;
        case MD_BLOCK_TR:       RENDER_LITERAL(r, "<tr>\n"); break;
        case MD_BLOCK_TH:       render_open_td_block(r, "th", cast(MD_BLOCK_TD_DETAIL*)detail); break;
        case MD_BLOCK_TD:       render_open_td_block(r, "td", cast(MD_BLOCK_TD_DETAIL*)detail); break;
        default: assert(false);
    }

    return 0;
}

int leave_block_callback(MD_BLOCKTYPE type, void* detail, void* userdata)
{
    static immutable(MD_CHAR)*[6] head = [ "</h1>\n", "</h2>\n", "</h3>\n", "</h4>\n", "</h5>\n", "</h6>\n" ];
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;

    switch(type) {
        case MD_BLOCK_DOC:      /*noop*/ break;
        case MD_BLOCK_QUOTE:    RENDER_LITERAL(r, "</blockquote>\n"); break;
        case MD_BLOCK_UL:       RENDER_LITERAL(r, "</ul>\n"); break;
        case MD_BLOCK_OL:       RENDER_LITERAL(r, "</ol>\n"); break;
        case MD_BLOCK_LI:       RENDER_LITERAL(r, "</li>\n"); break;
        case MD_BLOCK_HR:       /*noop*/ break;
        case MD_BLOCK_H:        RENDER_LITERAL(r, head[(cast(MD_BLOCK_H_DETAIL*)detail).level - 1]); break;
        case MD_BLOCK_CODE:     RENDER_LITERAL(r, "</code></pre>\n"); break;
        case MD_BLOCK_HTML:     /* noop */ break;
        case MD_BLOCK_P:        RENDER_LITERAL(r, "</p>\n"); break;
        case MD_BLOCK_TABLE:    RENDER_LITERAL(r, "</table>\n"); break;
        case MD_BLOCK_THEAD:    RENDER_LITERAL(r, "</thead>\n"); break;
        case MD_BLOCK_TBODY:    RENDER_LITERAL(r, "</tbody>\n"); break;
        case MD_BLOCK_TR:       RENDER_LITERAL(r, "</tr>\n"); break;
        case MD_BLOCK_TH:       RENDER_LITERAL(r, "</th>\n"); break;
        case MD_BLOCK_TD:       RENDER_LITERAL(r, "</td>\n"); break;
        default: assert(false);
    }

    return 0;
}

int enter_span_callback(MD_SPANTYPE type, void* detail, void* userdata)
{
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;

    if(r.image_nesting_level > 0) {
        /* We are inside an image, i.e. rendering the ALT attribute of
         * <IMG> tag. */
        return 0;
    }

    switch(type) {
        case MD_SPAN_EM:                RENDER_LITERAL(r, "<em>"); break;
        case MD_SPAN_STRONG:            RENDER_LITERAL(r, "<strong>"); break;
        case MD_SPAN_A:                 render_open_a_span(r, cast(MD_SPAN_A_DETAIL*) detail); break;
        case MD_SPAN_IMG:               render_open_img_span(r, cast(MD_SPAN_IMG_DETAIL*) detail); break;
        case MD_SPAN_CODE:              RENDER_LITERAL(r, "<code>"); break;
        case MD_SPAN_DEL:               RENDER_LITERAL(r, "<del>"); break;
        case MD_SPAN_LATEXMATH:         RENDER_LITERAL(r, "<equation>"); break;
        case MD_SPAN_LATEXMATH_DISPLAY: RENDER_LITERAL(r, "<equation type=\"display\">"); break;
        default: assert(false);
    }

    return 0;
}

int leave_span_callback(MD_SPANTYPE type, void* detail, void* userdata)
{
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;

    if(r.image_nesting_level > 0) {
        /* We are inside an image, i.e. rendering the ALT attribute of
         * <IMG> tag. */
        if(r.image_nesting_level == 1  &&  type == MD_SPAN_IMG)
            render_close_img_span(r, cast(MD_SPAN_IMG_DETAIL*) detail);
        return 0;
    }

    switch(type) {
        case MD_SPAN_EM:                RENDER_LITERAL(r, "</em>"); break;
        case MD_SPAN_STRONG:            RENDER_LITERAL(r, "</strong>"); break;
        case MD_SPAN_A:                 RENDER_LITERAL(r, "</a>"); break;
        case MD_SPAN_IMG:               /*noop, handled above*/ break;
        case MD_SPAN_CODE:              RENDER_LITERAL(r, "</code>"); break;
        case MD_SPAN_DEL:               RENDER_LITERAL(r, "</del>"); break;
        case MD_SPAN_LATEXMATH:         /*fall through*/
        case MD_SPAN_LATEXMATH_DISPLAY: RENDER_LITERAL(r, "</equation>"); break;
        default: assert(false);
    }

    return 0;
}

int text_callback(MD_TEXTTYPE type, const(MD_CHAR)* text, MD_SIZE size, void* userdata)
{
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;

    switch(type) {
        case MD_TEXT_NULLCHAR:  render_utf8_codepoint(r, 0x0000, &render_text); break;
        case MD_TEXT_BR:        RENDER_LITERAL(r, (r.image_nesting_level == 0 ? "<br />\n" : " ")); break;
        case MD_TEXT_SOFTBR:    RENDER_LITERAL(r, (r.image_nesting_level == 0 ? "\n" : " ")); break;
        case MD_TEXT_HTML:      render_text(r, text, size); break;
        case MD_TEXT_ENTITY:    render_entity(r, text, size, &render_html_escaped); break;
        default:                render_html_escaped(r, text, size); break;
    }

    return 0;
}

void debug_log_callback(const(char)* msg, void* userdata)
{
    MD_RENDER_HTML* r = cast(MD_RENDER_HTML*) userdata;
    if(r.flags & MD_RENDER_FLAG_DEBUG)
        fprintf(stderr, "MD4C: %s\n", msg);
}


/* Render Markdown into HTML.
 *
 * Note only contents of <body> tag is generated. Caller must generate
 * HTML header/footer manually before/after calling md_render_html().
 *
 * Params input and input_size specify the Markdown input.
 * Callback process_output() gets called with chunks of HTML output.
 * (Typical implementation may just output the bytes to file or append to
 * some buffer).
 * Param userdata is just propagated back to process_output() callback.
 * Param parser_flags are flags from md4c.h propagated to md_parse().
 * Param render_flags is bitmask of MD_RENDER_FLAG_xxxx.
 *
 * Returns -1 on error (if md_parse() fails.)
 * Returns 0 on success.
 */
int md_render_html(const(MD_CHAR)* input, MD_SIZE input_size,
                   void function(const(MD_CHAR)*, MD_SIZE, void*) nothrow @nogc process_output,
                   void* userdata, uint parser_flags, uint renderer_flags)
{
    MD_RENDER_HTML render = MD_RENDER_HTML(process_output, userdata, renderer_flags, 0);
    render.escape_map[] = '\x00';

    MD_PARSER parser = MD_PARSER(
        0,
        parser_flags,
        &enter_block_callback,
        &leave_block_callback,
        &enter_span_callback,
        &leave_span_callback,
        &text_callback,
        &debug_log_callback,
        null
    );

    render.escape_map['"'] = 1;
    render.escape_map['&'] = 1;
    render.escape_map['<'] = 1;
    render.escape_map['>'] = 1;

    return md_parse(input, input_size, &parser, cast(void*) &render);
}

