/**
  * Create SQL queries from string containing D expressions.

  * This module allows you to generate SQL from a template, containing D expressions. Depending on these expressions
  * parts of the template will be included in the SQL or not.

  * Authors: Robert Klotzner, robert.klotzner at gmail.com
  * Date: January 7, 2013
  * License: GNU General Public License version 3 <http://www.gnu.org/licenses/>
  * Copyright: 2013 Robert Klotzner

  * Bugs: Unicode not really supported. I haven't really explored that yet, but
  * I believe that at the moment string processing will fail for multibyte
  * utf-8 characters in the input string.
  */
module arsd.querygenerator;

import std.exception;
import std.uni;
import std.string;
import std.variant;
import std.conv;
import std.typetuple;


/**
  * The generated query + args.
  * 
  * It offers support for concatenation, so you can create your query in parts and concatenate them afterwards.
  * Ths string prepend will be inserted inbetween two CreatedQuery.query strings at concatation if and only if both query strings are non empty.
  * The resulting CreatedQuery has a prepend string equal to the one of the left side of the '~' operation.

  * Beware that because of the handling of the prepend string, the result of multiple concatenations depends on the order of evaluation (if empty strings are involved).
  *  You might need parantheses or splitting
  * it up in multiple statements to achieve the desired effect.
  */
struct CreatedQuery {
    /**
      * Concatenation with automatically inserted prepend string in between.

      * The prepend string gets inserted inbetween the two query strings if and only if both query strings are non empty.
      * The prepend string of the resulting object is the one of the left object. Thus the resulting object depends on the order of execution if empty strings are involved.
      * See the unittest to this struct for details.
      */
    CreatedQuery opBinary(string op)(CreatedQuery right) if(op=="~") {
        CreatedQuery res=this;
        res~=right;
        return res;
    }

    CreatedQuery opBinary(string op)(string right) if(op=="~") {
        CreatedQuery res=this;
        res.query~=right;
        return res;
    }

    CreatedQuery opBinaryRight(string op)(string left) if(op=="~") {
        CreatedQuery res=this;
        res.query=left~res.query;
        return res;
    }

    
    ref CreatedQuery opOpAssign(string op)(string right) if(op=="~") {
        query~=right;
        return this;
    }
    ref CreatedQuery opOpAssign(string op)(CreatedQuery right) if(op=="~") {
        query~=(query.length && right.query.length) ?  right.prepend : "";
        query~=right.query;
        args~=right.args;
        return this;
    }
    /// Currently not const because of bug:
    ///     http://d.puremagic.com/issues/show_bug.cgi?id=8759
    bool opEquals( CreatedQuery other) {
        return query==other.query && args==other.args && prepend==other.prepend;
    }
    string query;
    Variant[] args;
    string prepend;
}

unittest {
    auto q1=CreatedQuery("select * from table");
    CreatedQuery q2=CreatedQuery("", [], " where ");
    auto q3=CreatedQuery("col1=? and col2=?", [Variant(7), Variant("huhu")], " and ");
    auto q4=(q1~(q2~q3));
    q1~=q2~q3;
    import std.stdio;
    writefln("q4: %s, q1: %s", q4, q1);
    assert(q4==q1);
    assert(q1==CreatedQuery("select * from table where col1=? and col2=?", [Variant(7), Variant("huhu")], ""));
}

/**
  * This method generates D code from the preSql data, which can be mixed in for generating the resulting sql and the resulting Variant[] array.
  * The variable sql_ will contain the generated SQL.
  * The variable args_ is the Variant[] array.
  * Use createQuery for directly generating the resulting SQL and args.
  * Params:
  *     preSql = The to be processed SQL containing D expressions in #{} blocks, sub blocks in {} and declarations in ${}.
  * Returns: D code which can be mixed in.
**/
string createQueryGenerator(string preSql) {
    string out_cmd;
    out_cmd~="string sql_;\n";
    out_cmd~="Variant[] args_;\n";
    out_cmd~="with(data_) {\n";
    out_cmd~=preSqlParser(preSql);
    out_cmd~="\n}";
    return out_cmd;
}

/**
  * Uses createQueryGenerator for actually doing the job.
  * data_ will be made available with D's 'with' statement to the embedded code in queryString. So you can access the elements just as regular variables.
  *
  * Params: 
  *     queryString = An SQL template. An SQL consists of nested blocks. The
  *                   uppermost block is the queryString itself, you create subblocks by
  *                   enclosing it in braces '{}'.

                      __Declaration part__

                      Each block might start with a declaration part. It does
                      so if the first character in the block is a '$'. The
                      declaration part ends with a colon ':'.
                      It consists of declarations which start with '${' and end
                      with '}'. Two types of declarations are allowed:

                      1. variable assignment of the form: ${a=5}    This will
                      result in a D expression in the generated code of the
                      form 'auto a=5;'.

                      2. Foreach loop declaration. This one might only occur
                      once in the declaration part and causes the block in
                      which it is declared to be executed in a loop.
                        It looks like: ${a in someArray}

                      3. Special assignment of ${queryGenSep=" or "} : This one
                      is specially treated. If you specified a loop the
                      generated string of each iteration will be concatenated
                      and the queryGenSep will be used to separate them. If you
                      don't specify one, the default will be " or ".

                      Variable assignments before the optional loop declaration
                      will be declared outside the loop, the ones after the
                      loop declaration will be declared within the loop and
                      might access the loop variable, ('a' in our case).

                      Multiple declarations of the form '${}' might be present
                      within the declaration part, they may be separated with
                      white space. 

                      __Body part__

                      If no declaration part is present, then the whole content
                      of the block is the body part. (This is if the first
                      character is no '$'.) Otherwise it starts with the colon
                      at the end of the declaration part.

                      Everything in the body part will be echoed to the
                      resulting SQL so you can just write plain SQL now. There
                      are only a few exceptions:

                      1. A '{' will introduce a child block.

                      2. A '#{' will start a D expression, which ends with
                      another '}'

                      3. A '$' will trigger an error as it is only valid in the
                      declaration part.

                      4. SQL string which can either start with " or with ' it
                      might contain any of '{' '}' '$' '#' they all will be
                      ignored within a string. Apart from this, no escaping of
                      these characters is possible at the moment.

                      __D expression__

                      A D expression might occur any amount of times within the
                      body part of a block. It contents will be evaluated as D
                      code. Which must evaluate to some value. If this value is
                      different from the value's types init value it is
                      considered valid, then it will be included in the Variant[] array and a '?'
                      gets inserted into the resulting SQL. If the returned value equals the type's
                      init value then no '?' gets inserted and the value will not be present in the
                      args array.

                      So if the D expression evaluates to a string and is the
                      empty string, it will not be included.

                      The expression is contained within #{ D expression }.

                      The D code has access to the passed params via params[0]
                      .. params[n], all declarations made in the declarations
                      parts of the blocks above it and the contents of the data_ struct.
                      It is made available with D's 'with' statement so
                      data_.foo will just be
                      'foo'.

                      __Blocks__
                        
                      Blocks are the building blocks of the resulting
                      expression. If a block contains a D expression or a
                      subblock which contains D expressions, then its contents
                      will only be included in the output if at least one of
                      the D expressions are valid. (Different from their init
                              value). So if you have a SQL expression of the
                      form {someColumn=#{some D code}} there will be no output
                      at all if #{some D code} was not valid. If a block does
                      not contain any D code and neither do any sub blocks then
                      its output will be included in the output, of the
                      containing block. Which in turn will only be emitted if
                      this block either has no D expressions at all or at least
                      on of the is valid.

                      The second property that makes blocks useful is that if a block produces no output, for the above mentioned reasons, then the text before it will be dropped
                      if there were D expression found already. It will also be dropped if the preceding block vanished. This way you can concatenate blocks with ' and ' and ' or '
                      and they will be dropped if not applicable. A leading ' where ' on the other hand would not be dropped in any case, except the whole output vanishes.

                      For examples, see the unittests, a more complex example, I used in reality is here:
                        `({${db=params[0]} : `
                                    `{`
                                        `${d in datespan} ${arData=db.autoRunData(d.autorun)}: {({date>=#{d.from}} and {date<=#{d.to}} and `
                                        `{({task_run.id>=#{arData.firstId==long.max ? 0 : arData.firstId}} and {task_run.id<=#{arData.lastId}} and {comment like #{d.autorun.length ? "%:Autorun:"~d.autorun~":Autorun:%" : ""}})})}`
                                    `}`
                                    `})`

                    Right at the start I am starting the uppermost block with a
                    '(' which means it has no declaration part, then I start
                    the first sub block, followed by declaration I needed.
                    Then I start another block with '{' followed by a loop
                    declaration (d will iterate over the datespan array which
                            comes from the data_ struct) followed by an inner
                    variable declaration of arData, you can see both d (the
                            looping variable) and db from the outer block are
                    accessible. Afterwards the body starts, which starts with a
                    block containing '(' and subblocks of a comparisons with a D
                    expression like {({date>=#{d.from}})}.
                    If all D expressions in the block like d.from evaluate to
                    an empty string, the whole containig block will not produce
                    any output. So not even '()' this is because they are
                    enclused in a subblock. The 'and' between {date>=#{d.from}}
                    and {date<=#{d.to}}  for example will only appear in the
                    output if both d.from and d.to contained a valid non empty
                    string.

                    The outputs of each loop iteration will be separated with " or " by default,
                    you can change this by setting queryGenSep in the declaration part. 

  */
CreatedQuery createQuery(string queryString, StructT, Params...)(StructT data_, Params params) {
    debug(queryGenerator) import std.stdio;
    mixin(createQueryGenerator(queryString));
    debug(queryGenerator) writeln("Generated: ", createQueryGenerator(queryString));
    return CreatedQuery(sql_, args_);
    //return CreatedQuery.init;
}

unittest {
    import std.stdio;
    struct Test1 {
        string a;
        string b;
    }
    struct Test {
        Test1[] foo;
        string bar;
        int k;
    }
    Test t1;
    CreatedQuery myQuery(Test t1) {
        return createQuery!`select * from testtable where 
        {({${queryGenSep=" or "} ${f in foo} : ({col1=#{f.a}} and {col2=#{f.b}})})} or 
        {col3>#{k}}`(t1);
    }
    auto res=myQuery(t1);
    writeln("Result with empty args: ", res.query);
    assert(res.args==[]);
    t1.k=9;
    res=myQuery(t1);
    writefln("Result with k set: %s, args: %s", res.query, res.args);
    assert(res.args==[Variant(9)]);
    t1.foo~=Test1(string.init, "Hallo du da!");
    res=myQuery(t1);
    writeln("Result with foo.b and k set: ", res.query);
    assert(res.args==[Variant("Hallo du da!"), Variant(9)]);
    t1.foo~=Test1("Hallo du da!", string.init);
    res=myQuery(t1);
    writeln("Result with foo0.b and foo1.a and k set: ", res.query);
    assert(res.args==[Variant("Hallo du da!"), Variant("Hallo du da!"), Variant(9)]);
    t1.foo~=Test1("Hello!", "Cu!");
    res=myQuery(t1);
    writeln("Result with foo0.b and foo1.a and foo2.a and foo2.b and k set: ", res.query);
    assert(res.args==[Variant("Hallo du da!"), Variant("Hallo du da!"), Variant("Hello!"), Variant("Cu!"), Variant(9)]);
}

private:
void dropWhite(ref string buf) {
    buf=buf.stripLeft();
}

/// D's indexOf seemed not to work at compile time.
size_t indexOf(string heap, char needle) {
    foreach(i, c; heap) {
        if(needle==c) {
            return i;
        }
    }
    return -1;
}
//pragma(msg, createQueryGenerator( " (${item in datespan} : ( { date>=#{item.from} and} {date<=#{item.to} and} {comment like #{\"%:Autorun:\"~item.autorun~\":Autorun:%\"}})"));
//pragma(msg, createQueryGenerator( " Hello this is a test!"));
//pragma(msg, createQueryGenerator( `  ${item in datespan} : ( { date>=#{item.from} } and {date<=#{item.to} } and {comment like #{"%:Autorun:"~item.autorun~":Autorun:%"}})`));
//pragma(msg, createQueryGenerator(`select * from testtable where 
        //{({${queryGenSep=" or "} ${f in foo} : ({col1=#{f.a}} and {col2=#{f.b}})})} or 
        //{col3>k}`));

//Syntax:
// ${a=3} ${i in array} ${u=i.c} : some data #{D expression} { same again }
// presql : [decls :] body
// decls : [${variable=assignment}]* [${variable in array}] [${variable=assignment}]*
// body : [some_string | #{D expression} | {presql}]*
/// private
/// Handles the part before the ":" colon. (Variable declarations + loop declaration)
private static string doVariableProcessing(ref string part, int level) {
    string output;
    string for_each_decl;
    string after_output;
    bool queryGenSepFound=false;
    string buf="buf"~to!string(level);
    dropWhite(part);
    assert(part);
    immutable isFirst="isFirst"~to!string(level);
    if(part[0]!='$')  {
        return "bool "~isFirst~"=false;\n"~"{\nstring "~buf~";\n";
    }
    output~="bool "~isFirst~"=true;\n";
    while(true) {
        assert(part.length>2);
        assert(part[0]=='$', "Only declarations enclosed in '${' are allowed in declarations block. Invalid data found: "~part);
        assert(part[1]=='{', "'{' in '${' is mandatory! Found at:"~part);
        string var_name;
        part=part[2..$];
        foreach(i,c; part) {
            if(!c.isAlpha()) {
                var_name=part[0..i];
                if(var_name=="queryGenSep") {
                    var_name="queryGenSep"~to!string(level);
                    queryGenSepFound=true;
                }
                part=part[i..$];
                break;
            }
        }
        dropWhite(part);
        assert(part.length, "Unexpected end of data, expected '=' or 'in'");
        enum Operation {
            assignment,
            in_array
        }
        Operation op;
        switch(part[0]) {
            case '=': op=Operation.assignment;
                      part=part[1..$];
                      break;
            case 'i':
                      assert(part.length>1 && part[1]=='n', "Expected 'n' after 'i' forming 'in', got: "~part);
                      part=part[2..$];
                      op=Operation.in_array;
                      break;
            default: assert(false, "Unexpected operation: Only variable assignment ('=') and array loop ('in') are supported, found at: "~part);

        }
        dropWhite(part);
        string right_side;
        foreach(i, c; part) {
            if(c=='}') {
                right_side=part[0..i];
                part=part[i+1..$];
                break;
            }
        }
        if(op==Operation.assignment) {
            string buff="auto "~var_name~"="~right_side~";\n";
            if(for_each_decl)
                after_output~=buff;
            else
                output~=buff;
        }
        else {
            if(for_each_decl)
                assert(false, "Only one foreach declaration allowed, found second at: "~part);
            for_each_decl="\nforeach("~var_name~"; "~right_side~") {\n";
        }
        dropWhite(part);
        if(part[0]==':') {
            part=part[1..$];
            if(!queryGenSepFound) {
                output~="immutable queryGenSep"~to!string(level)~"=\" or \";\n";
            }
            for_each_decl = for_each_decl==[] ? "{\n" : for_each_decl;
            after_output~="string "~buf~";\n";
            after_output~="if(!"~isFirst~") {\n";
            after_output~=buf~"=queryGenSep"~to!string(level)~";\n}\n";
            return output~for_each_decl~after_output;
        }
        else {
            assert(part, "Unexpected end of string, expected another declaration '${}' or ':'.");
            assert(part[0]=='$', "Expected ':' or another variable assignment ('$'), at: "~part);
        }
    }
}

// Extracts a D expression (#{}) from the string.
string dExpressionParser(ref string data, string buf, string validCount, string slevel, ref int count) {
    assert(data.length>2 && data[0]=='#' && data[1]=='{');
    string out_cmd;
    data=data[2..$];
    auto end=data.indexOf('}');
    assert(end>0, "Empty or non closed D expression found at: "~data);
    string val="val"~slevel~"_"~to!string(count);
    out_cmd~="auto "~val~"="~data[0..end]~";\n";
    out_cmd~="if("~val~"!=typeof("~val~").init) {\n";
    out_cmd~="debug(queryGenerator) writeln(\"Found valid value: \", "~val~");\n";
    out_cmd~=validCount~"++;\n";
    out_cmd~=buf~"~=\"?\";\n";
    out_cmd~="args_~=Variant("~val~");\n}\n";
    out_cmd~="else {\ndebug(queryGenerator) writeln(\"Found invalid value: \", "~val~");\n}\n";
    data=data[end+1..$];
    return out_cmd;
}
// do the parsing of an sql string ('....' or ".....") Also handles escaping ('') or ("")
string processString(ref string data, string buf) {
    assert(data[0]=='\'' || data[0]=='"', "Expected ' or \"");
    char begin=data[0];
    data=data[1..$];
    string out_cmd;
    while(data.length) {
        foreach(i, c; data) {
            if(c==begin && ((i+1)>=data.length || data[i+1]!=begin) ) { // End of string (Ignore escaped end in string)
                out_cmd~=buf~"~=`"~begin~data[0..i]~begin~"`;\n";
                data=data[i+1 .. $];
                break;
            }
        }
    }
    return out_cmd;
}

// Parsing starts here.
string preSqlParser(ref string data, int level=0) {
    auto out_cmd="{\n";
    out_cmd~=doVariableProcessing(data, level);
    debug(querygenerator) import std.stdio;
    // dropWhite(data); //(Maybe intended, so don't drop it)
    immutable slevel=to!string(level);
    immutable buf="buf"~slevel;
    immutable text="text"~slevel;
    string upperBuf;
    string upperWasValid;
    int dexprCount=0;
    if(level>0) {
        upperBuf="buf"~(to!string(level-1));
        upperWasValid="wasValid"~(to!string(level-1));
    }
    else
        upperBuf="sql_";

    immutable validCount="validCount"~slevel;
    immutable wasValid="wasValid"~slevel;
    immutable isFirst="isFirst"~to!string(level); // Defined in doVariableProcessing
    out_cmd~="int "~validCount~"=-1;\n";
    out_cmd~="int "~wasValid~";\n"; // Tri state: 0 not valid; -1 valid (was just text); >0 valid (contained valid D expressions)
    out_cmd~="string "~text~";\n";
    while(data.length) {
        auto end=data.length;
        foreach(i, c; data) {
            if(c=='{' || c=='}' || c=='#' || c=='\'' || c=='"' || c=='$') {
                end=i;
                break;
            }
        }
        out_cmd~=text~"=`"~data[0..end]~"`;\n";
        out_cmd~=buf~"~=`"~data[0..end]~"`;\n"; 
        data=data[end..$];
        if(data.length==0) 
            break;
        debug(querygenerator) writefln("Remaining (level: %s) data: %s", level, data);
        switch(data[0]) {
            case '{' : 
                assert(data.length>2, "Expected some data after '{' at: "~data);
                data=data[1..$];
                out_cmd~="if("~validCount~"==0) {\n";
                out_cmd~=buf~"="~buf~"[0..$-"~text~".length];\n}\n";

                out_cmd~=preSqlParser(data, level+1); 

                assert(data[0]=='}', "Expected closing '}', got: "~data);
                data=data[1..$];

                out_cmd~="if("~wasValid~"==0 && "~validCount~">0) {\n"; // validCount has to be greater than 0 otherwise we have removed the data already. (See above)
                out_cmd~=buf~"="~buf~"[0..$-"~text~".length];\n}\n";
                out_cmd~="if("~wasValid~">0 || "~wasValid~"==0) {\n";
                out_cmd~=validCount~"="~validCount~"==-1 ? "~wasValid~" : "~validCount~"+"~wasValid~";\n";
                out_cmd~="}\n";
                break;
            case '}' : 
                goto finish;
            case '#' :
                out_cmd~="if("~validCount~"==-1) {\n\t";
                out_cmd~=validCount~"=0;\n}\n";
                out_cmd~=dExpressionParser(data, buf, validCount, slevel, dexprCount);
                dexprCount++;
                break;
            case '\'':
            case '"':
                out_cmd~=processString(data, buf);
                break;
            case '$': assert(false, "Unexpected '$'. The variable declaration block must start with a '${}' declaration otherwise you are already in the body and '${}' declarations are invalid.\n Found at: "~data);
            default:
                assert(false, "WTF? The if should have made this impossible!");
        }
    }
finish:
    out_cmd~=`debug(queryGenerator) writefln("Leaving level: %s, valid count: %s, buffer: %s", `~slevel~`, `~validCount~`, `~buf~" );\n";
    out_cmd~="if("~validCount~"==-1 || "~validCount~">0) {\n";
    out_cmd~="debug(queryGenerator) writeln(\"Appended "~buf~" with contents: \", "~buf~");\n";
    out_cmd~=isFirst~"=false;\n"; // No longer the first valid run, so separator should be inserted.
    out_cmd~=upperBuf~"~="~buf~";\n}\n";
    if(level>0) {
        out_cmd~=upperWasValid~"="~validCount~";\n";
    }
    // End of loop:
    out_cmd~="}\n";
    if(level>0)
        out_cmd~="if("~isFirst~") "~upperWasValid~"=0;\n"; // In case loop wasn't executed a single time.
    out_cmd~="}\n";
    return out_cmd;
}
