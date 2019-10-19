/++
	A module mostly copied from https://github.com/trishume/ddbus
+/
module arsd.dbus;

pragma(lib, "dbus-1");

import core.time : Duration;
import std.meta;
import std.string;
import std.typecons;
import std.exception;
import std.traits;
import std.conv;
import std.range;
import std.algorithm;

import core.memory;
import std.array;
import std.format;

import std.meta : AliasSeq, staticIndexOf;
import std.range;
import std.traits;
import std.variant : VariantN;


/++
  Flags for use with dbusMarshaling UDA

  Default is to include public fields only
+/
enum MarshalingFlag : ubyte {
  includePrivateFields = 1 << 0,  /// Automatically include private fields
  manualOnly           = 1 << 7   /// Only include fields with explicit
                                  ///   `@Yes.DBusMarshal`. This overrides any
                                  ///   `include` flags.
}

/++
  UDA for specifying DBus marshaling options on structs
+/
auto dbusMarshaling(Args)(Args args ...)
  if (allSatisfy!(isMarshalingFlag, Args)) {
  return BitFlags!MarshalingFlag(args);
}

private template isAllowedField(alias field) {
  private enum flags = marshalingFlags!(__traits(parent, field));
  private alias getUDAs!(field, Flag!"DBusMarshal") UDAs;

  static if (UDAs.length != 0) {
    static assert (UDAs.length == 1,
      "Only one UDA of type Flag!\"DBusMarshal\" allowed on struct field.");
    static assert (is(typeof(UDAs[0]) == Flag!"DBusMarshal"),
      "Did you intend to add UDA Yes.DBusMarshal or No.DBusMarshal?");
    enum isAllowedField = cast(bool) UDAs[0];
  } else static if (!(flags & MarshalingFlag.manualOnly)) {
    static if (__traits(getProtection, field) == "public")
      enum isAllowedField = true;
    else static if (cast(bool) (flags & MarshalingFlag.includePrivateFields))
      enum isAllowedField = true;
    else
      enum isAllowedField = false;
  } else
    enum isAllowedField = false;
}

private template isMarshalingFlag(T) {
  enum isMarshalingFlag = is(T == MarshalingFlag);
}

private template marshalingFlags(S) if (is(S == struct)) {
  private alias getUDAs!(S, BitFlags!MarshalingFlag) UDAs;

  static if (UDAs.length == 0)
    enum marshalingFlags = BitFlags!MarshalingFlag.init;
  else {
    static assert (UDAs.length == 1,
      "Only one @dbusMarshaling UDA allowed on type.");
    static assert (is(typeof(UDAs[0]) == BitFlags!MarshalingFlag),
      "Huh? Did you intend to use @dbusMarshaling UDA?");
    enum marshalingFlags = UDAs[0];
  }
}

struct DictionaryEntry(K, V) {
  K key;
  V value;
}

auto byDictionaryEntries(K, V)(V[K] aa) {
  return aa.byKeyValue.map!(pair => DictionaryEntry!(K, V)(pair.key, pair.value));
}

template VariantType(T) {
  alias VariantType = TemplateArgsOf!(T)[0];
}

template allCanDBus(TS...) {
  static if (TS.length == 0) {
    enum allCanDBus = true; 
  } else static if(!canDBus!(TS[0])) {
    enum allCanDBus = false;
  } else {
    enum allCanDBus = allCanDBus!(TS[1..$]);
  }
}

/++
  AliasSeq of all basic types in terms of the DBus typesystem
 +/
private // Don't add to the API yet, 'cause I intend to move it later
alias BasicTypes = AliasSeq!(
  bool,
  byte,
  short,
  ushort,
  int,
  uint,
  long,
  ulong,
  double,
  string,
  ObjectPath
);

template basicDBus(T) {
  static if(staticIndexOf!(T, BasicTypes) >= 0) {
    enum basicDBus = true;
  } else static if(is(T B == enum)) {
    enum basicDBus = basicDBus!B;
  } else static if(isInstanceOf!(BitFlags, T)) {
    alias TemplateArgsOf!T[0] E;
    enum basicDBus = basicDBus!E;
  } else {
    enum basicDBus = false;
  }
}

template canDBus(T) {
  static if(basicDBus!T || is(T == DBusAny)) {
    enum canDBus = true;
  } else static if(isInstanceOf!(Variant, T)) {
    enum canDBus = canDBus!(VariantType!T);
  } else static if(isInstanceOf!(VariantN, T)) {
    // Phobos-style variants are supported if limited to DBus compatible types.
    enum canDBus = (T.AllowedTypes.length > 0) && allCanDBus!(T.AllowedTypes);
  } else static if(isTuple!T) {
    enum canDBus = allCanDBus!(T.Types);
  } else static if(isInputRange!T) {
    static if(is(ElementType!T == DictionaryEntry!(K, V), K, V)) {
      enum canDBus = basicDBus!K && canDBus!V;
    } else {
      enum canDBus = canDBus!(ElementType!T);
    }
  } else static if(isAssociativeArray!T) {
    enum canDBus = basicDBus!(KeyType!T) && canDBus!(ValueType!T);
  } else static if(is(T == struct) && !isInstanceOf!(DictionaryEntry, T)) {
    enum canDBus = allCanDBus!(AllowedFieldTypes!T);
  } else {
    enum canDBus = false;
  }
}

string typeSig(T)() if(canDBus!T) {
  static if(is(T == byte)) {
    return "y";
  } else static if(is(T == bool)) {
    return "b";
  } else static if(is(T == short)) {
    return "n";
  } else static if(is(T == ushort)) {
    return "q";
  } else static if(is(T == int)) {
    return "i";
  } else static if(is(T == uint)) {
    return "u";
  } else static if(is(T == long)) {
    return "x";
  } else static if(is(T == ulong)) {
    return "t";
  } else static if(is(T == double)) {
    return "d";
  } else static if(is(T == string)) {
    return "s";
  } else static if(is(T == ObjectPath)) {
    return "o";
  } else static if(isInstanceOf!(Variant, T) || isInstanceOf!(VariantN, T)) {
    return "v";
  } else static if(is(T B == enum)) {
    return typeSig!B;
  } else static if(isInstanceOf!(BitFlags, T)) {
    alias TemplateArgsOf!T[0] E;
    return typeSig!E;
  } else static if(is(T == DBusAny)) {
    static assert(false, "Cannot determine type signature of DBusAny. Change to Variant!DBusAny if a variant was desired.");
  } else static if(isTuple!T) {
    string sig = "(";
    foreach(i, S; T.Types) {
      sig ~= typeSig!S();
    } 
    sig ~= ")";
    return sig;
  } else static if(isInputRange!T) {
    return "a" ~ typeSig!(ElementType!T)();
  } else static if(isAssociativeArray!T) {
    return "a{" ~ typeSig!(KeyType!T) ~ typeSig!(ValueType!T) ~ "}";
  } else static if(is(T == struct)) {
    string sig = "(";
    foreach(i, S; AllowedFieldTypes!T) {
      sig ~= typeSig!S();
    }
    sig ~= ")";
    return sig;
  }
}

string typeSig(T)() if(isInstanceOf!(DictionaryEntry, T)) {
  alias typeof(T.key) K;
  alias typeof(T.value) V;
  return "{" ~ typeSig!K ~ typeSig!V ~ '}';
}

string[] typeSigReturn(T)() if(canDBus!T) {
  static if(is(T == Tuple!TS, TS...))
    return typeSigArr!TS;
  else
    return [typeSig!T];
}

string typeSigAll(TS...)() if(allCanDBus!TS) {
  string sig = "";
  foreach(i,T; TS) {
    sig ~= typeSig!T();
  }
  return sig;
}

string[] typeSigArr(TS...)() if(allCanDBus!TS) {
  string[] sig = [];
  foreach(i,T; TS) {
    sig ~= typeSig!T();
  }
  return sig;
}

int typeCode(T)() if(canDBus!T) {
  int code = typeSig!T()[0];
  return (code != '(') ? code : 'r';
}

int typeCode(T)() if(isInstanceOf!(DictionaryEntry, T) && canDBus!(T[])) {
  return 'e';
}

private template AllowedFieldTypes(S) if (is(S == struct)) {
  static alias TypeOf(alias sym) = typeof(sym);

  alias AllowedFieldTypes =
    staticMap!(TypeOf, Filter!(isAllowedField, S.tupleof));
}

struct ObjectPath {
  private string _value;

  this(string objPath) pure @safe {
    enforce(isValid(objPath));
    _value = objPath;
  }

  string toString() const {
    return _value;
  }

  /++
    Returns the string representation of this ObjectPath.
   +/
  string value() const pure @nogc nothrow @safe {
    return _value;
  }

  size_t toHash() const pure @nogc nothrow @trusted {
    return hashOf(_value);
  }

  bool opEquals(ref const typeof(this) b) const pure @nogc nothrow @safe {
    return _value == b._value;
  }

  ObjectPath opBinary(string op : "~")(string rhs) const pure @safe {
    if (!rhs.startsWith("/"))
      return opBinary!"~"(ObjectPath("/" ~ rhs));
    else
      return opBinary!"~"(ObjectPath(rhs));
  }

  ObjectPath opBinary(string op : "~")(ObjectPath rhs) const pure @safe
  in {
    assert(ObjectPath.isValid(_value) && ObjectPath.isValid(rhs._value));
  } out (v) {
    assert(ObjectPath.isValid(v._value));
  } body {
    ObjectPath ret;

    if (_value == "/")
      ret._value = rhs._value;
    else
      ret._value = _value ~ rhs._value;

    return ret;
  }

  void opOpAssign(string op : "~")(string rhs) pure @safe {
    _value = opBinary!"~"(rhs)._value;
  }

  void opOpAssign(string op : "~")(ObjectPath rhs) pure @safe {
    _value = opBinary!"~"(rhs)._value;
  }

  /++
    Returns: `false` for empty strings or strings that don't match the
    pattern `(/[0-9A-Za-z_]+)+|/`.
   +/
  static bool isValid(string objPath) pure @nogc nothrow @safe {
    import std.ascii : isAlphaNum;

    if (!objPath.length)
      return false;
    if (objPath == "/")
      return true;
    if (objPath[0] != '/' || objPath[$ - 1] == '/')
      return false;
    // .representation to avoid unicode exceptions -> @nogc & nothrow
    return objPath.representation.splitter('/').drop(1)
      .all!(a =>
        a.length &&
        a.all!(c =>
          c.isAlphaNum || c == '_'
        )
      );
  }
}

/// Structure allowing typeless parameters
struct DBusAny {
  /// DBus type of the value (never 'v'), see typeSig!T
  int type;
  /// Child signature for Arrays & Tuples
  string signature;
  /// If true, this value will get serialized as variant value, otherwise it is serialized like it wasn't in a DBusAny wrapper.
  /// Same functionality as Variant!T but with dynamic types if true.
  bool explicitVariant;

  union
  {
    ///
    byte int8;
    ///
    short int16;
    ///
    ushort uint16;
    ///
    int int32;
    ///
    uint uint32;
    ///
    long int64;
    ///
    ulong uint64;
    ///
    double float64;
    ///
    string str;
    ///
    bool boolean;
    ///
    ObjectPath obj;
    ///
    DBusAny[] array;
    ///
    alias tuple = array;
    ///
    DictionaryEntry!(DBusAny, DBusAny)* entry;
    ///
    ubyte[] binaryData;
  }

  /// Manually creates a DBusAny object using a type, signature and implicit specifier.
  this(int type, string signature, bool explicit) {
    this.type = type;
    this.signature = signature;
    this.explicitVariant = explicit;
  }

  /// Automatically creates a DBusAny object with fitting parameters from a D type or Variant!T.
  /// Pass a `Variant!T` to make this an explicit variant.
  this(T)(T value) {
    static if(is(T == byte) || is(T == ubyte)) {
      this(typeCode!byte, null, false);
      int8 = cast(byte) value;
    } else static if(is(T == short)) {
      this(typeCode!short, null, false);
      int16 = cast(short) value;
    } else static if(is(T == ushort)) {
      this(typeCode!ushort, null, false);
      uint16 = cast(ushort) value;
    } else static if(is(T == int)) {
      this(typeCode!int, null, false);
      int32 = cast(int) value;
    } else static if(is(T == uint)) {
      this(typeCode!uint, null, false);
      uint32 = cast(uint) value;
    } else static if(is(T == long)) {
      this(typeCode!long, null, false);
      int64 = cast(long) value;
    } else static if(is(T == ulong)) {
      this(typeCode!ulong, null, false);
      uint64 = cast(ulong) value;
    } else static if(is(T == double)) {
      this(typeCode!double, null, false);
      float64 = cast(double) value;
    } else static if(isSomeString!T) {
      this(typeCode!string, null, false);
      str = value.to!string;
    } else static if(is(T == bool)) {
      this(typeCode!bool, null, false);
      boolean = cast(bool) value;
    } else static if(is(T == ObjectPath)) {
      this(typeCode!ObjectPath, null, false);
      obj = value;
    } else static if(is(T == Variant!R, R)) {
      static if(is(R == DBusAny)) {
        type = value.data.type;
        signature = value.data.signature;
        explicitVariant = true;
        if(type == 'a' || type == 'r') {
          if(signature == ['y'])
            binaryData = value.data.binaryData;
          else
            array = value.data.array;
        } else if(type == 's')
          str = value.data.str;
        else if(type == 'e')
          entry = value.data.entry;
        else
          uint64 = value.data.uint64;
      } else {
        this(value.data);
        explicitVariant = true;
      }
    } else static if(is(T : DictionaryEntry!(K, V), K, V)) {
      this('e', null, false);
      entry = new DictionaryEntry!(DBusAny, DBusAny)();
      static if(is(K == DBusAny))
        entry.key = value.key;
      else
        entry.key = DBusAny(value.key);
      static if(is(V == DBusAny))
        entry.value = value.value;
      else
        entry.value = DBusAny(value.value);
    } else static if(is(T == ubyte[]) || is(T == byte[])) {
      this('a', ['y'], false);
      binaryData = cast(ubyte[]) value;
    } else static if(isInputRange!T) {
      this.type = 'a';
      static assert(!is(ElementType!T == DBusAny), "Array must consist of the same type, use Variant!DBusAny or DBusAny(tuple(...)) instead");
      static assert(.typeSig!(ElementType!T) != "y");
      this.signature = .typeSig!(ElementType!T);
      this.explicitVariant = false;
      foreach(elem; value)
        array ~= DBusAny(elem);
    } else static if(isTuple!T) {
      this.type = 'r';
      this.signature = ['('];
      this.explicitVariant = false;
      foreach(index, R; value.Types) {
        auto var = DBusAny(value[index]);
        tuple ~= var;
        if(var.explicitVariant)
          this.signature ~= 'v';
        else {
          if (var.type != 'r')
            this.signature ~= cast(char) var.type;
          if(var.type == 'a' || var.type == 'r')
            this.signature ~= var.signature;
        }
      }
      this.signature ~= ')';
    } else static if(isAssociativeArray!T) {
      this(value.byDictionaryEntries);
    } else static assert(false, T.stringof ~ " not convertible to a Variant");
  }

  ///
  string toString() const {
    string valueStr;
    switch(type) {
    case typeCode!byte:
      valueStr = int8.to!string;
      break;
    case typeCode!short:
      valueStr = int16.to!string;
      break;
    case typeCode!ushort:
      valueStr = uint16.to!string;
      break;
    case typeCode!int:
      valueStr = int32.to!string;
      break;
    case typeCode!uint:
      valueStr = uint32.to!string;
      break;
    case typeCode!long:
      valueStr = int64.to!string;
      break;
    case typeCode!ulong:
      valueStr = uint64.to!string;
      break;
    case typeCode!double:
      valueStr = float64.to!string;
      break;
    case typeCode!string:
      valueStr = '"' ~ str ~ '"';
      break;
    case typeCode!ObjectPath:
      valueStr = '"' ~ obj.to!string ~ '"';
      break;
    case typeCode!bool:
      valueStr = boolean ? "true" : "false";
      break;
    case 'a':
      import std.digest : toHexString;

      if(signature == ['y'])
        valueStr = "binary(" ~ binaryData.toHexString ~ ')';
      else
        valueStr = '[' ~ array.map!(a => a.toString).join(", ") ~ ']';
      break;
    case 'r':
      valueStr = '(' ~ tuple.map!(a => a.toString).join(", ") ~ ')';
      break;
    case 'e':
      valueStr = entry.key.toString ~ ": " ~ entry.value.toString;
      break;
    default:
      valueStr = "unknown";
      break;
    }
    return "DBusAny(" ~ cast(char) type
      ~ ", \"" ~ signature.idup
      ~ "\", " ~ (explicitVariant ? "explicit" : "implicit")
      ~ ", " ~ valueStr ~ ")";
  }

  /++
    Get the value stored in the DBusAny object.

    Parameters:
      T = The requested type. The currently stored value must match the
        requested type exactly.

    Returns:
      The current value of the DBusAny object.

    Throws:
      TypeMismatchException if the DBus type of the current value of the
      DBusAny object is not the same as the DBus type used to represent T.
  +/
  T get(T)() @property const
    if(staticIndexOf!(T, BasicTypes) >= 0)
  {
    enforce(type == typeCode!T,
      new TypeMismatchException(
        "Cannot get a " ~ T.stringof ~ " from a DBusAny with"
          ~ " a value of DBus type '" ~ typeSig ~ "'.", typeCode!T, type));

    static if(isIntegral!T) {
      enum memberName =
        (isUnsigned!T ? "uint" : "int") ~ (T.sizeof * 8).to!string;
      return __traits(getMember, this, memberName);
    } else static if(is(T == double)) {
      return float64;
    } else static if(is(T == string)) {
      return str;
    } else static if(is(T == ObjectPath)) {
      return obj;
    } else static if(is(T == bool)) {
      return boolean;
    } else {
      static assert(false);
    }
  }

  /// ditto
  T get(T)() @property const
    if(is(T == const(DBusAny)[]))
  {
    enforce((type == 'a' && signature != "y") || type == 'r',
      new TypeMismatchException(
        "Cannot get a " ~ T.stringof ~ " from a DBusAny with"
          ~ " a value of DBus type '" ~ this.typeSig ~ "'.",
        typeCode!T, type));

    return array;
  }

  /// ditto
  T get(T)() @property const
    if (is(T == const(ubyte)[]))
  {
    enforce(type == 'a' && signature == "y",
      new TypeMismatchException(
        "Cannot get a " ~ T.stringof ~ " from a DBusAny with"
          ~ " a value of DBus type '" ~ this.typeSig ~ "'.",
        typeCode!T, type));

    return binaryData;
  }

  /// If the value is an array of DictionaryEntries this will return a HashMap
  DBusAny[DBusAny] toAA() {
    enforce(type == 'a' && signature && signature[0] == '{');
    DBusAny[DBusAny] aa;
    foreach(val; array) {
      enforce(val.type == 'e');
      aa[val.entry.key] = val.entry.value;
    }
    return aa;
  }

  /++
    Get the DBus type signature of the value stored in the DBusAny object.

    Returns:
      The type signature of the value stored in this DBusAny object.
   +/
  string typeSig() @property const pure nothrow @safe
  {
    if(type == 'a') {
      return "a" ~ signature;
    } else if(type == 'r') {
      return signature;
    } else if(type == 'e') {
      return () @trusted {
        return "{" ~ entry.key.signature ~ entry.value.signature ~ "}";
      } ();
    } else {
      return [ cast(char) type ];
    }
  }

  /// Converts a basic type, a tuple or an array to the D type with type checking. Tuples can get converted to an array too.
  T to(T)() {
    static if(is(T == Variant!R, R)) {
      static if(is(R == DBusAny)) {
        auto v = to!R;
        v.explicitVariant = false;
        return Variant!R(v);
      } else
        return Variant!R(to!R);
    } else static if(is(T == DBusAny)) {
      return this;
    } else static if(isIntegral!T || isFloatingPoint!T) {
      switch(type) {
      case typeCode!byte:
        return cast(T) int8;
      case typeCode!short:
        return cast(T) int16;
      case typeCode!ushort:
        return cast(T) uint16;
      case typeCode!int:
        return cast(T) int32;
      case typeCode!uint:
        return cast(T) uint32;
      case typeCode!long:
        return cast(T) int64;
      case typeCode!ulong:
        return cast(T) uint64;
      case typeCode!double:
        return cast(T) float64;
      default:
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
      }
    } else static if(is(T == bool)) {
      if(type == 'b')
        return boolean;
      else
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
    } else static if(isSomeString!T) {
      if(type == 's')
        return str.to!T;
      else if(type == 'o')
        return obj.toString();
      else
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
    } else static if(is(T == ObjectPath)) {
      if(type == 'o')
        return obj;
      else
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
    } else static if(isDynamicArray!T) {
      if(type != 'a' && type != 'r')
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to an array");
      T ret;
      if(signature == ['y']) {
        static if(isIntegral!(ElementType!T))
          foreach(elem; binaryData)
            ret ~= elem.to!(ElementType!T);
      } else
        foreach(elem; array)
          ret ~= elem.to!(ElementType!T);
      return ret;
    } else static if(isTuple!T) {
      if(type != 'r')
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
      T ret;
      enforce(ret.Types.length == tuple.length, "Tuple length mismatch");
      foreach(index, T; ret.Types)
        ret[index] = tuple[index].to!T;
      return ret;
    } else static if(isAssociativeArray!T) {
      if(type != 'a' || !signature || signature[0] != '{')
        throw new Exception("Can't convert type " ~ cast(char) type ~ " to " ~ T.stringof);
      T ret;
      foreach(pair; array) {
        enforce(pair.type == 'e');
        ret[pair.entry.key.to!(KeyType!T)] = pair.entry.value.to!(ValueType!T);
      }
      return ret;
    } else static assert(false, "Can't convert variant to " ~ T.stringof);
  }

  bool opEquals(ref in DBusAny b) const {
    if(b.type != type || b.explicitVariant != explicitVariant)
      return false;
    if((type == 'a' || type == 'r') && b.signature != signature)
      return false;
    if(type == 'a' && signature == ['y'])
      return binaryData == b.binaryData;
    if(type == 'a')
      return array == b.array;
    else if(type == 'r')
      return tuple == b.tuple;
    else if(type == 's')
      return str == b.str;
    else if(type == 'o')
      return obj == b.obj;
    else if(type == 'e')
      return entry == b.entry || (entry && b.entry && *entry == *b.entry);
    else
      return uint64 == b.uint64;
  }
}

/// Marks the data as variant on serialization
struct Variant(T) {
  ///
  T data;
}

Variant!T variant(T)(T data) {
  return Variant!T(data);
}

enum MessageType {
  Invalid = 0,
  Call, Return, Error, Signal
}

void emitSignal(Args...)(Connection conn, string path, string iface, string name, Args args) {
	Message msg = Message(null, path, iface, name, true);
	msg.build(args);
	conn.send(msg);
}

struct Message {
  DBusMessage *msg;

  this(string dest, string path, string iface, string method, bool signal = false) {
    if(signal)
        msg = dbus_message_new_signal(path.toStringz(), iface.toStringz(), method.toStringz());
    else
        msg = dbus_message_new_method_call(dest.toStringz(), path.toStringz(), iface.toStringz(), method.toStringz());
  }

  this(DBusMessage *m) {
    msg = m;
  }

  this(this) {
    dbus_message_ref(msg);
  }

  ~this() {
    dbus_message_unref(msg);
  }

  void build(TS...)(TS args) if(allCanDBus!TS) {
    DBusMessageIter iter;
    dbus_message_iter_init_append(msg, &iter);
    buildIter(&iter, args);
  }

  /**
     Reads the first argument of the message.
     Note that this creates a new iterator every time so calling it multiple times will always
     read the first argument. This is suitable for single item returns.
     To read multiple arguments use readTuple.
  */
  T read(T)() if(canDBus!T) {
    DBusMessageIter iter;
    dbus_message_iter_init(msg, &iter);
    return readIter!T(&iter);
  }
  alias read to;

  Tup readTuple(Tup)() if(isTuple!Tup && allCanDBus!(Tup.Types)) {
    DBusMessageIter iter;
    dbus_message_iter_init(msg, &iter);
    Tup ret;
    readIterTuple(&iter, ret);
    return ret;
  }

  Message createReturn() {
    return Message(dbus_message_new_method_return(msg));
  }

  MessageType type() {
    return cast(MessageType)dbus_message_get_type(msg);
  }

  bool isCall() {
    return type() == MessageType.Call;
  }

  // Various string members
  // TODO: make a mixin to avoid this copy-paste
  string signature() {
    const(char)* cStr = dbus_message_get_signature(msg);
    assert(cStr != null);
    return cStr.fromStringz().idup;
  }
  string path() {
    const(char)* cStr = dbus_message_get_path(msg);
    assert(cStr != null);
    return cStr.fromStringz().idup;
  }
  string iface() {
    const(char)* cStr = dbus_message_get_interface(msg);
    assert(cStr != null);
    return cStr.fromStringz().idup;
  }
  string member() {
    const(char)* cStr = dbus_message_get_member(msg);
    assert(cStr != null);
    return cStr.fromStringz().idup;
  }
  string sender() {
    const(char)* cStr = dbus_message_get_sender(msg);
    assert(cStr != null);
    return cStr.fromStringz().idup;
  }
}

struct Connection {
  DBusConnection *conn;
  this(DBusConnection *connection) {
    conn = connection;
  }

  this(this) {
    dbus_connection_ref(conn);
  }

  ~this() {
    dbus_connection_unref(conn);
  }

  void close() {
    dbus_connection_close(conn);
  }

  void send(Message msg) {
    dbus_connection_send(conn,msg.msg, null);
  }

  void sendBlocking(Message msg) {
    send(msg);
    dbus_connection_flush(conn);
  }

  Message sendWithReplyBlocking(Message msg, int timeout = -1) {
    DBusMessage *dbusMsg = msg.msg;
    dbus_message_ref(dbusMsg);
    DBusMessage *reply = wrapErrors((err) {
        auto ret = dbus_connection_send_with_reply_and_block(conn,dbusMsg,timeout,err);
        dbus_message_unref(dbusMsg);
        return ret;
      });
    return Message(reply);
  }

  Message sendWithReplyBlocking(Message msg, Duration timeout) {
    return sendWithReplyBlocking(msg, timeout.total!"msecs"().to!int);
  }
}

Connection connectToBus(DBusBusType bus = DBusBusType.DBUS_BUS_SESSION) {
  DBusConnection *conn = wrapErrors((err) { return dbus_bus_get(bus,err); });
  return Connection(conn);
}

class PathIface {
  this(Connection conn, string dest, ObjectPath path, string iface) {
    this(conn, dest, path.value, iface);
  }

  this(Connection conn, string dest, string path, string iface) {
    this.conn = conn;
    this.dest = dest.toStringz();
    this.path = path.toStringz();
    this.iface = iface.toStringz();
  }

  Ret call(Ret, Args...)(string meth, Args args) if(allCanDBus!Args && canDBus!Ret) {
    Message msg = Message(dbus_message_new_method_call(dest,path,iface,meth.toStringz()));
    msg.build(args);
    Message ret = conn.sendWithReplyBlocking(msg);
    return ret.read!Ret();
  }

  Message opDispatch(string meth, Args...)(Args args) {
    Message msg = Message(dbus_message_new_method_call(dest,path,iface,meth.toStringz()));
    msg.build(args);
    return conn.sendWithReplyBlocking(msg);
  }

  Connection conn;
  const(char)* dest;
  const(char)* path;
  const(char)* iface;
}

enum SignalMethod;

/**
   Registers all *possible* methods of an object in a router.
   It will not register methods that use types that ddbus can't handle.

   The implementation is rather hacky and uses the compiles trait to check for things
   working so if some methods randomly don't seem to be added, you should probably use
   setHandler on the router directly. It is also not efficient and creates a closure for every method.

   TODO: replace this with something that generates a wrapper class who's methods take and return messages
   and basically do what MessageRouter.setHandler does but avoiding duplication. Then this DBusWrapper!Class
   could be instantiated with any object efficiently and placed in the router table with minimal duplication.
 */
void registerMethods(T : Object)(MessageRouter router, string path, string iface, T obj) {
  MessagePattern patt = MessagePattern(path,iface,"",false);
  foreach(member; __traits(allMembers, T)) {
    static if (__traits(compiles, __traits(getOverloads, obj, member))
               && __traits(getOverloads, obj, member).length > 0
               && __traits(compiles, router.setHandler(patt, &__traits(getOverloads,obj,member)[0]))) {
      patt.method = member;
      patt.signal = hasUDA!(__traits(getOverloads,obj,member)[0], SignalMethod);
      router.setHandler(patt, &__traits(getOverloads,obj,member)[0]);
    }
  }
}

struct MessagePattern {
  string path;
  string iface;
  string method;
  bool signal;

  this(Message msg) {
    path = msg.path();
    iface = msg.iface();
    method = msg.member();
    signal = (msg.type() == MessageType.Signal);
  }

  this(string path, string iface, string method, bool signal = false) {
    this.path = path;
    this.iface = iface;
    this.method = method;
    this.signal = signal;
  }

  size_t toHash() const @safe nothrow {
    size_t hash = 0;
    auto stringHash = &(typeid(path).getHash);
    hash += stringHash(&path);
    hash += stringHash(&iface);
    hash += stringHash(&method);
    hash += (signal?1:0);
    return hash;
  }

  bool opEquals(ref const typeof(this) s) const @safe pure nothrow {
    return (path == s.path) && (iface == s.iface) && (method == s.method) && (signal == s.signal);
  }
}

struct MessageHandler {
  alias HandlerFunc = void delegate(Message call, Connection conn);
  HandlerFunc func;
  string[] argSig;
  string[] retSig;
}

class MessageRouter {
  MessageHandler[MessagePattern] callTable;

  bool handle(Message msg, Connection conn) {
    MessageType type = msg.type();
    if(type != MessageType.Call && type != MessageType.Signal)
      return false;
    auto pattern = MessagePattern(msg);
    // import std.stdio; debug writeln("Handling ", pattern);

    if(pattern.iface == "org.freedesktop.DBus.Introspectable" &&
      pattern.method == "Introspect" && !pattern.signal) {
      handleIntrospect(pattern.path, msg, conn);
      return true;
    }

    MessageHandler* handler = (pattern in callTable);
    if(handler is null) return false;

    // Check for matching argument types
    version(DDBusNoChecking) {

    } else {
      if(!equal(join(handler.argSig), msg.signature())) {
        return false;
      }
    }

    handler.func(msg,conn);
    return true;
  }

  void setHandler(Ret, Args...)(MessagePattern patt, Ret delegate(Args) handler) {
    void handlerWrapper(Message call, Connection conn) {
      Tuple!Args args = call.readTuple!(Tuple!Args)();
      auto retMsg = call.createReturn();
      static if(!is(Ret == void)) {
        Ret ret = handler(args.expand);
        static if (is(Ret == Tuple!T, T...))
          retMsg.build!T(ret.expand);
        else
          retMsg.build(ret);
      } else {
        handler(args.expand);
      }
      if(!patt.signal)
        conn.send(retMsg);
    }
    static string[] args = typeSigArr!Args;
    static if(is(Ret==void)) {
      static string[] ret = [];
    } else {
      static string[] ret = typeSigReturn!Ret;
    }
    MessageHandler handleStruct = {func: &handlerWrapper, argSig: args, retSig: ret};
    callTable[patt] = handleStruct;
  }

  static string introspectHeader = `<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node name="%s">`;

  string introspectXML(string path) {
    auto methods = callTable.byKey().filter!(a => (a.path == path) && !a.signal)().array()
      // .schwartzSort!((a) => a.iface, "a<b")();
      .sort!((a,b) => a.iface < b.iface)();
    auto ifaces = methods.groupBy();
    auto app = appender!string;
    formattedWrite(app,introspectHeader,path);
    foreach(iface; ifaces) {
      formattedWrite(app,`<interface name="%s">`,iface.front.iface);
      foreach(methodPatt; iface.array()) {
        formattedWrite(app,`<method name="%s">`,methodPatt.method);
        auto handler = callTable[methodPatt];
        foreach(arg; handler.argSig) {
          formattedWrite(app,`<arg type="%s" direction="in"/>`,arg);
        }
        foreach(arg; handler.retSig) {
          formattedWrite(app,`<arg type="%s" direction="out"/>`,arg);
        }
        app.put("</method>");
      }
      app.put("</interface>");
    }

    string childPath = path;
    if(!childPath.endsWith("/")) {
      childPath ~= "/";
    }
    auto children = callTable.byKey().filter!(a => (a.path.startsWith(childPath)) && !a.signal)()
      .map!((s) => s.path.chompPrefix(childPath))
      .map!((s) => s.splitter('/').front)
      .array().sort().uniq();
    foreach(child; children) {
      formattedWrite(app,`<node name="%s"/>`,child);
    }

    app.put("</node>");
    return app.data;
  }

  void handleIntrospect(string path, Message call, Connection conn) {
    auto retMsg = call.createReturn();
    retMsg.build(introspectXML(path));
    conn.sendBlocking(retMsg);
  }
}

extern(C) private DBusHandlerResult filterFunc(DBusConnection *dConn, DBusMessage *dMsg, void *routerP) {
  MessageRouter router = cast(MessageRouter)routerP;
  dbus_message_ref(dMsg);
  Message msg = Message(dMsg);
  dbus_connection_ref(dConn);
  Connection conn = Connection(dConn);
  bool handled = router.handle(msg, conn);
  if(handled) {
    return DBusHandlerResult.DBUS_HANDLER_RESULT_HANDLED;
  } else {
    return DBusHandlerResult.DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
  }
}

extern(C) private void unrootUserData(void *userdata) {
  GC.removeRoot(userdata);
}

void registerRouter(Connection conn, MessageRouter router) {
  void *routerP = cast(void*)router;
  GC.addRoot(routerP);
  dbus_connection_add_filter(conn.conn, &filterFunc, routerP, &unrootUserData);
}

private T wrapErrors(T)(
  T delegate(DBusError *err) del,
  string file = __FILE__,
  size_t line = __LINE__,
  Throwable next = null
) {
  DBusError error;
  dbus_error_init(&error);
  T ret = del(&error);
  if(dbus_error_is_set(&error)) {
    auto ex = new DBusException(&error, file, line, next);
    dbus_error_free(&error);
    throw ex;
  }
  return ret;
}

/++
  Thrown when a DBus error code was returned by libdbus.
+/
class DBusException : Exception {
  private this(
    scope DBusError *err,
    string file = __FILE__,
    size_t line = __LINE__,
    Throwable next = null
  ) pure nothrow {

    super(err.message.fromStringz().idup, file, line, next);
  }
}

/++
  Thrown when the signature of a message does not match the requested types or
  when trying to get a value from a DBusAny object that does not match the type
  of its actual value.
+/
class TypeMismatchException : Exception {
  private this(
    int expectedType,
    int actualType,
    string file = __FILE__,
    size_t line = __LINE__,
    Throwable next = null
  ) pure nothrow @safe {
    string message;

    if (expectedType == 'v') {
      message = "The type of value at the current position in the message is"
        ~ " incompatible to the target variant type."
        ~ " Type code of the value: '" ~ cast(char) actualType ~ '\'';
    } else {
      message = "The type of value at the current position in the message does"
        ~ " not match the type of value to be read."
        ~ " Expected: '" ~ cast(char) expectedType ~ "',"
        ~ " Got: '" ~ cast(char) actualType ~ '\'';
    }

    this(message, expectedType, actualType, file, line, next);
  }

  this(
    string message,
    int expectedType,
    int actualType,
    string file = __FILE__,
    size_t line = __LINE__,
    Throwable next = null
  ) pure nothrow @safe {
    _expectedType = expectedType;
    _actualType = actualType;
    super(message, file, line, next);
  }

  int expectedType() @property pure const nothrow @safe @nogc {
    return _expectedType;
  }

  int actualType() @property pure const nothrow @safe @nogc {
    return _actualType;
  }

  private:
  int _expectedType;
  int _actualType;
}

/++
  Thrown during type conversion between DBus types and D types when a value is
  encountered that can not be represented in the target type.

  This exception should not normally be thrown except when dealing with D types
  that have a constrained value set, such as Enums.
+/
class InvalidValueException : Exception {
  private this(Source)(
    Source value,
    string targetType,
    string file = __FILE__,
    size_t line = __LINE__,
    Throwable next = null
  ) {
    import std.conv : to;

    static if(__traits(compiles, value.to!string))
      string valueString = value.to!string;
    else
      string valueString = "(unprintable)";

    super("Value " ~ valueString ~ " cannot be represented in type " ~ targetType);
  }
}

import std.exception : enforce;
import std.meta: allSatisfy;
import std.range;
import std.traits;
import std.variant : VariantN;

void buildIter(TS...)(DBusMessageIter *iter, TS args) if(allCanDBus!TS) {
  foreach(index, arg; args) {
    alias TS[index] T;
    static if(is(T == string)) {
      immutable(char)* cStr = arg.toStringz();
      dbus_message_iter_append_basic(iter,typeCode!T,&cStr);
    } else static if(is(T == ObjectPath)) {
      immutable(char)* cStr = arg.toString().toStringz();
      dbus_message_iter_append_basic(iter,typeCode!T,&cStr);
    } else static if(is(T==bool)) {
      dbus_bool_t longerBool = arg; // dbus bools are ints
      dbus_message_iter_append_basic(iter,typeCode!T,&longerBool);
    } else static if(isTuple!T) {
      DBusMessageIter sub;
      dbus_message_iter_open_container(iter, 'r', null, &sub);
      buildIter(&sub, arg.expand);
      dbus_message_iter_close_container(iter, &sub);
    } else static if(isInputRange!T) {
      DBusMessageIter sub;
      const(char)* subSig = (typeSig!(ElementType!T)()).toStringz();
      dbus_message_iter_open_container(iter, 'a', subSig, &sub);
      foreach(x; arg) {
        static if(isInstanceOf!(DictionaryEntry, typeof(x))) {
          DBusMessageIter entry;
          dbus_message_iter_open_container(&sub, 'e', null, &entry);
          buildIter(&entry, x.key);
          buildIter(&entry, x.value);
          dbus_message_iter_close_container(&sub, &entry);
        } else {
          buildIter(&sub, x);
        }
      }
      dbus_message_iter_close_container(iter, &sub);
    } else static if(isAssociativeArray!T) {
      DBusMessageIter sub;
      const(char)* subSig = typeSig!T[1..$].toStringz();
      dbus_message_iter_open_container(iter, 'a', subSig, &sub);
      foreach(k, v; arg) {
        DBusMessageIter entry;
        dbus_message_iter_open_container(&sub, 'e', null, &entry);
        buildIter(&entry, k);
        buildIter(&entry, v);
        dbus_message_iter_close_container(&sub, &entry);
      }
      dbus_message_iter_close_container(iter, &sub);
    } else static if(isInstanceOf!(VariantN, T)) {
      enforce(arg.hasValue,
        new InvalidValueException(arg, "dbus:" ~ cast(char) typeCode!T));

      DBusMessageIter sub;
      foreach(AT; T.AllowedTypes) {
        if (arg.peek!AT) {
          dbus_message_iter_open_container(iter, 'v', typeSig!AT.ptr, &sub);
          buildIter(&sub, arg.get!AT);
          dbus_message_iter_close_container(iter, &sub);
          break;
        }
      }
    } else static if(is(T == DBusAny) || is(T == Variant!DBusAny)) {
      static if(is(T == Variant!DBusAny)) {
        auto val = arg.data;
        val.explicitVariant = true;
      } else {
        auto val = arg;
      }
      DBusMessageIter subStore;
      DBusMessageIter* sub = &subStore;
      const(char)[] sig = [ cast(char) val.type ];
      if(val.type == 'a')
        sig ~= val.signature;
      else if(val.type == 'r')
        sig = val.signature;
      sig ~= '\0';
      if (!val.explicitVariant)
        sub = iter;
      else
        dbus_message_iter_open_container(iter, 'v', sig.ptr, sub);
      if(val.type == 's') {
        buildIter(sub, val.str);
      } else if(val.type == 'o') {
        buildIter(sub, val.obj);
      } else if(val.type == 'b') {
        buildIter(sub,val.boolean);
      } else if(dbus_type_is_basic(val.type)) {
        dbus_message_iter_append_basic(sub,val.type,&val.int64);
      } else if(val.type == 'a') {
        DBusMessageIter arr;
        dbus_message_iter_open_container(sub, 'a', sig[1 .. $].ptr, &arr);
        if (val.signature == ['y'])
          foreach (item; val.binaryData)
            dbus_message_iter_append_basic(&arr, 'y', &item);
        else
          foreach(item; val.array)
            buildIter(&arr, item);
        dbus_message_iter_close_container(sub, &arr);
      } else if(val.type == 'r') {
        DBusMessageIter arr;
        dbus_message_iter_open_container(sub, 'r', null, &arr);
        foreach(item; val.tuple)
          buildIter(&arr, item);
        dbus_message_iter_close_container(sub, &arr);
      } else if(val.type == 'e') {
        DBusMessageIter entry;
        dbus_message_iter_open_container(sub, 'e', null, &entry);
        buildIter(&entry, val.entry.key);
        buildIter(&entry, val.entry.value);
        dbus_message_iter_close_container(sub, &entry);
      }
      if(val.explicitVariant)
        dbus_message_iter_close_container(iter, sub);
    } else static if(isInstanceOf!(Variant, T)) {
      DBusMessageIter sub;
      const(char)* subSig = typeSig!(VariantType!T).toStringz();
      dbus_message_iter_open_container(iter, 'v', subSig, &sub);
      buildIter(&sub, arg.data);
      dbus_message_iter_close_container(iter, &sub);
    } else static if(is(T == struct)) {
      DBusMessageIter sub;
      dbus_message_iter_open_container(iter, 'r', null, &sub);

      // Following failed because of missing 'this' for members of arg.
      // That sucks. It worked without Filter.
      // Reported: https://issues.dlang.org/show_bug.cgi?id=17692
//    buildIter(&sub, Filter!(isAllowedField, arg.tupleof));

      // Using foreach to work around the issue
      foreach(i, member; arg.tupleof) {
        // Ugly, but we need to use tupleof again in the condition, because when
        // we use `member`, isAllowedField will fail because it'll find this
        // nice `buildIter` function instead of T when it looks up the parent
        // scope of its argument.
        static if (isAllowedField!(arg.tupleof[i]))
          buildIter(&sub, member);
      }

      dbus_message_iter_close_container(iter, &sub);
    } else static if(basicDBus!T) {
      dbus_message_iter_append_basic(iter,typeCode!T,&arg);
    }
  }
}

T readIter(T)(DBusMessageIter *iter) if (is(T == enum)) {
  import std.algorithm.searching : canFind;

  alias OriginalType!T B;

  B value = readIter!B(iter);
  enforce(
    only(EnumMembers!T).canFind(value),
    new InvalidValueException(value, T.stringof)
  );
  return cast(T) value;
}

T readIter(T)(DBusMessageIter *iter) if (isInstanceOf!(BitFlags, T)) {
  import std.algorithm.iteration : fold;

  alias TemplateArgsOf!T[0] E;
  alias OriginalType!E B;

  B mask = only(EnumMembers!E).fold!((a, b) => cast(B) (a | b));

  B value = readIter!B(iter);
  enforce(
    !(value & ~mask),
    new InvalidValueException(value, T.stringof)
  );

  return T(cast(E) value);
}

T readIter(T)(DBusMessageIter *iter) if (!is(T == enum) && !isInstanceOf!(BitFlags, T) && canDBus!T) {
  auto argType = dbus_message_iter_get_arg_type(iter);
  T ret;

  static if(!isInstanceOf!(Variant, T) || is(T == Variant!DBusAny)) {
    if(argType == 'v') {
      DBusMessageIter sub;
      dbus_message_iter_recurse(iter, &sub);
      static if(is(T == Variant!DBusAny)) {
        ret = variant(readIter!DBusAny(&sub));
      } else {
        ret = readIter!T(&sub);
        static if(is(T == DBusAny))
          ret.explicitVariant = true;
      }
      dbus_message_iter_next(iter);
      return ret;
    }
  }

  static if(
    !is(T == DBusAny)
    && !is(T == Variant!DBusAny)
    && !isInstanceOf!(VariantN, T)
  ) {
    enforce(argType == typeCode!T(),
      new TypeMismatchException(typeCode!T(), argType));
  }
  static if(is(T==string) || is(T==ObjectPath)) {
    const(char)* cStr;
    dbus_message_iter_get_basic(iter, &cStr);
    string str = cStr.fromStringz().idup; // copy string
    static if(is(T==string))
      ret = str;
    else
      ret = ObjectPath(str);
  } else static if(is(T==bool)) {
    dbus_bool_t longerBool;
    dbus_message_iter_get_basic(iter, &longerBool);
    ret = cast(bool)longerBool;
  } else static if(isTuple!T) {
    DBusMessageIter sub;
    dbus_message_iter_recurse(iter, &sub);
    readIterTuple!T(&sub, ret);
  } else static if(is(T t : U[], U)) {
    assert(dbus_message_iter_get_element_type(iter) == typeCode!U);
    DBusMessageIter sub;
    dbus_message_iter_recurse(iter, &sub);
    while(dbus_message_iter_get_arg_type(&sub) != 0) {
      static if(is(U == DictionaryEntry!(K,V), K, V)) {
        DBusMessageIter entry;
        dbus_message_iter_recurse(&sub, &entry);
        ret ~= U(readIter!K(&entry), readIter!V(&entry));
        dbus_message_iter_next(&sub);
      } else {
        ret ~= readIter!U(&sub);
      }
    }
  } else static if(isInstanceOf!(Variant, T)) {
    DBusMessageIter sub;
    dbus_message_iter_recurse(iter, &sub);
    ret.data = readIter!(VariantType!T)(&sub);
  } else static if(isInstanceOf!(VariantN, T)) {
    scope const(char)[] argSig =
      dbus_message_iter_get_signature(iter).fromStringz();
    scope(exit)
      dbus_free(cast(void*) argSig.ptr);

    foreach(AT; T.AllowedTypes) {
      // We have to compare the full signature here, not just the typecode.
      // Otherwise, in case of container types, we might select the wrong one.
      // We would then be calling an incorrect instance of readIter, which would
      // probably throw a TypeMismatchException.
      if (typeSig!AT == argSig) {
        ret = readIter!AT(iter);
        break;
      }
    }

    // If no value is in ret, apparently none of the types matched.
    enforce(ret.hasValue, new TypeMismatchException(typeCode!T, argType));
  } else static if(isAssociativeArray!T) {
    DBusMessageIter sub;
    dbus_message_iter_recurse(iter, &sub);
    while(dbus_message_iter_get_arg_type(&sub) != 0) {
      DBusMessageIter entry;
      dbus_message_iter_recurse(&sub, &entry);
      auto k = readIter!(KeyType!T)(&entry);
      auto v = readIter!(ValueType!T)(&entry);
      ret[k] = v;
      dbus_message_iter_next(&sub);
    }
  } else static if(is(T == DBusAny)) {
    ret.type = argType;
    ret.explicitVariant = false;
    if(ret.type == 's') {
      ret.str = readIter!string(iter);
      return ret;
    } else if(ret.type == 'o') {
      ret.obj = readIter!ObjectPath(iter);
      return ret;
    } else if(ret.type == 'b') {
      ret.boolean = readIter!bool(iter);
      return ret;
    } else if(dbus_type_is_basic(ret.type)) {
      dbus_message_iter_get_basic(iter, &ret.int64);
    } else if(ret.type == 'a') {
      DBusMessageIter sub;
      dbus_message_iter_recurse(iter, &sub);
      auto sig = dbus_message_iter_get_signature(&sub);
      ret.signature = sig.fromStringz.dup;
      dbus_free(sig);
      if (ret.signature == ['y'])
        while(dbus_message_iter_get_arg_type(&sub) != 0) {
          ubyte b;
          assert(dbus_message_iter_get_arg_type(&sub) == 'y');
          dbus_message_iter_get_basic(&sub, &b);
          dbus_message_iter_next(&sub);
          ret.binaryData ~= b;
        }
      else
        while(dbus_message_iter_get_arg_type(&sub) != 0) {
          ret.array ~= readIter!DBusAny(&sub);
        }
    } else if(ret.type == 'r') {
      auto sig = dbus_message_iter_get_signature(iter);
      ret.signature = sig.fromStringz.dup;
      dbus_free(sig);
      DBusMessageIter sub;
      dbus_message_iter_recurse(iter, &sub);
      while(dbus_message_iter_get_arg_type(&sub) != 0) {
        ret.tuple ~= readIter!DBusAny(&sub);
      }
    } else if(ret.type == 'e') {
      DBusMessageIter sub;
      dbus_message_iter_recurse(iter, &sub);
      ret.entry = new DictionaryEntry!(DBusAny, DBusAny);
      ret.entry.key = readIter!DBusAny(&sub);
      ret.entry.value = readIter!DBusAny(&sub);
    }
  } else static if(is(T == struct)) {
    DBusMessageIter sub;
    dbus_message_iter_recurse(iter, &sub);
    readIterStruct!T(&sub, ret);
  } else static if(basicDBus!T) {
    dbus_message_iter_get_basic(iter, &ret);
  }

  dbus_message_iter_next(iter);
  return ret;
}

void readIterTuple(Tup)(DBusMessageIter *iter, ref Tup tuple) if(isTuple!Tup && allCanDBus!(Tup.Types)) {
  foreach(index, T; Tup.Types) {
    tuple[index] = readIter!T(iter);
  }
}

void readIterStruct(S)(DBusMessageIter *iter, ref S s) if(is(S == struct) && canDBus!S)
{
  foreach(index, T; Fields!S) {
    static if (isAllowedField!(s.tupleof[index])) {
      s.tupleof[index] = readIter!T(iter);
    }
  }
}

import core.stdc.config;
import core.stdc.stdarg;
extern (C) {
// START dbus/dbus-arch-deps.d
alias c_long dbus_int64_t;
alias c_ulong dbus_uint64_t;
alias int dbus_int32_t;
alias uint dbus_uint32_t;
alias short dbus_int16_t;
alias ushort dbus_uint16_t;
// END dbus/dbus-arch-deps.d
// START dbus/dbus-types.d
alias uint dbus_unichar_t;
alias uint dbus_bool_t;



struct DBus8ByteStruct
{
    dbus_uint32_t first32;
    dbus_uint32_t second32;
}

union DBusBasicValue
{
    ubyte[8] bytes;
    dbus_int16_t i16;
    dbus_uint16_t u16;
    dbus_int32_t i32;
    dbus_uint32_t u32;
    dbus_bool_t bool_val;
    dbus_int64_t i64;
    dbus_uint64_t u64;
    DBus8ByteStruct eight;
    double dbl;
    ubyte byt;
    char* str;
    int fd;
}
// END dbus/dbus-types.d
// START dbus/dbus-protocol.d

// END dbus/dbus-protocol.d
// START dbus/dbus-errors.d
struct DBusError
{
    const(char)* name;
    const(char)* message;
    uint dummy1;
    uint dummy2;
    uint dummy3;
    uint dummy4;
    uint dummy5;
    void* padding1;
}

void dbus_error_init (DBusError* error);
void dbus_error_free (DBusError* error);
void dbus_set_error (DBusError* error, const(char)* name, const(char)* message, ...);
void dbus_set_error_const (DBusError* error, const(char)* name, const(char)* message);
void dbus_move_error (DBusError* src, DBusError* dest);
dbus_bool_t dbus_error_has_name (const(DBusError)* error, const(char)* name);
dbus_bool_t dbus_error_is_set (const(DBusError)* error);
// END dbus/dbus-errors.d
// START dbus/dbus-macros.d

// END dbus/dbus-macros.d
// START dbus/dbus-memory.d
alias void function (void*) DBusFreeFunction;

void* dbus_malloc (size_t bytes);
void* dbus_malloc0 (size_t bytes);
void* dbus_realloc (void* memory, size_t bytes);
void dbus_free (void* memory);
void dbus_free_string_array (char** str_array);
void dbus_shutdown ();
// END dbus/dbus-memory.d
// START dbus/dbus-shared.d
enum DBusBusType
{
    DBUS_BUS_SESSION = 0,
    DBUS_BUS_SYSTEM = 1,
    DBUS_BUS_STARTER = 2
}

enum DBusHandlerResult
{
    DBUS_HANDLER_RESULT_HANDLED = 0,
    DBUS_HANDLER_RESULT_NOT_YET_HANDLED = 1,
    DBUS_HANDLER_RESULT_NEED_MEMORY = 2
}
// END dbus/dbus-shared.d
// START dbus/dbus-address.d
struct DBusAddressEntry;


dbus_bool_t dbus_parse_address (const(char)* address, DBusAddressEntry*** entry, int* array_len, DBusError* error);
const(char)* dbus_address_entry_get_value (DBusAddressEntry* entry, const(char)* key);
const(char)* dbus_address_entry_get_method (DBusAddressEntry* entry);
void dbus_address_entries_free (DBusAddressEntry** entries);
char* dbus_address_escape_value (const(char)* value);
char* dbus_address_unescape_value (const(char)* value, DBusError* error);
// END dbus/dbus-address.d
// START dbus/dbus-syntax.d
dbus_bool_t dbus_validate_path (const(char)* path, DBusError* error);
dbus_bool_t dbus_validate_interface (const(char)* name, DBusError* error);
dbus_bool_t dbus_validate_member (const(char)* name, DBusError* error);
dbus_bool_t dbus_validate_error_name (const(char)* name, DBusError* error);
dbus_bool_t dbus_validate_bus_name (const(char)* name, DBusError* error);
dbus_bool_t dbus_validate_utf8 (const(char)* alleged_utf8, DBusError* error);
// END dbus/dbus-syntax.d
// START dbus/dbus-signature.d
struct DBusSignatureIter
{
    void* dummy1;
    void* dummy2;
    dbus_uint32_t dummy8;
    int dummy12;
    int dummy17;
}

void dbus_signature_iter_init (DBusSignatureIter* iter, const(char)* signature);
int dbus_signature_iter_get_current_type (const(DBusSignatureIter)* iter);
char* dbus_signature_iter_get_signature (const(DBusSignatureIter)* iter);
int dbus_signature_iter_get_element_type (const(DBusSignatureIter)* iter);
dbus_bool_t dbus_signature_iter_next (DBusSignatureIter* iter);
void dbus_signature_iter_recurse (const(DBusSignatureIter)* iter, DBusSignatureIter* subiter);
dbus_bool_t dbus_signature_validate (const(char)* signature, DBusError* error);
dbus_bool_t dbus_signature_validate_single (const(char)* signature, DBusError* error);
dbus_bool_t dbus_type_is_valid (int typecode);
dbus_bool_t dbus_type_is_basic (int typecode);
dbus_bool_t dbus_type_is_container (int typecode);
dbus_bool_t dbus_type_is_fixed (int typecode);
// END dbus/dbus-signature.d
// START dbus/dbus-misc.d
char* dbus_get_local_machine_id ();
void dbus_get_version (int* major_version_p, int* minor_version_p, int* micro_version_p);
dbus_bool_t dbus_setenv (const(char)* variable, const(char)* value);
// END dbus/dbus-misc.d
// START dbus/dbus-threads.d
alias DBusMutex* function () DBusMutexNewFunction;
alias void function (DBusMutex*) DBusMutexFreeFunction;
alias uint function (DBusMutex*) DBusMutexLockFunction;
alias uint function (DBusMutex*) DBusMutexUnlockFunction;
alias DBusMutex* function () DBusRecursiveMutexNewFunction;
alias void function (DBusMutex*) DBusRecursiveMutexFreeFunction;
alias void function (DBusMutex*) DBusRecursiveMutexLockFunction;
alias void function (DBusMutex*) DBusRecursiveMutexUnlockFunction;
alias DBusCondVar* function () DBusCondVarNewFunction;
alias void function (DBusCondVar*) DBusCondVarFreeFunction;
alias void function (DBusCondVar*, DBusMutex*) DBusCondVarWaitFunction;
alias uint function (DBusCondVar*, DBusMutex*, int) DBusCondVarWaitTimeoutFunction;
alias void function (DBusCondVar*) DBusCondVarWakeOneFunction;
alias void function (DBusCondVar*) DBusCondVarWakeAllFunction;



enum DBusThreadFunctionsMask
{
    DBUS_THREAD_FUNCTIONS_MUTEX_NEW_MASK = 1,
    DBUS_THREAD_FUNCTIONS_MUTEX_FREE_MASK = 2,
    DBUS_THREAD_FUNCTIONS_MUTEX_LOCK_MASK = 4,
    DBUS_THREAD_FUNCTIONS_MUTEX_UNLOCK_MASK = 8,
    DBUS_THREAD_FUNCTIONS_CONDVAR_NEW_MASK = 16,
    DBUS_THREAD_FUNCTIONS_CONDVAR_FREE_MASK = 32,
    DBUS_THREAD_FUNCTIONS_CONDVAR_WAIT_MASK = 64,
    DBUS_THREAD_FUNCTIONS_CONDVAR_WAIT_TIMEOUT_MASK = 128,
    DBUS_THREAD_FUNCTIONS_CONDVAR_WAKE_ONE_MASK = 256,
    DBUS_THREAD_FUNCTIONS_CONDVAR_WAKE_ALL_MASK = 512,
    DBUS_THREAD_FUNCTIONS_RECURSIVE_MUTEX_NEW_MASK = 1024,
    DBUS_THREAD_FUNCTIONS_RECURSIVE_MUTEX_FREE_MASK = 2048,
    DBUS_THREAD_FUNCTIONS_RECURSIVE_MUTEX_LOCK_MASK = 4096,
    DBUS_THREAD_FUNCTIONS_RECURSIVE_MUTEX_UNLOCK_MASK = 8192,
    DBUS_THREAD_FUNCTIONS_ALL_MASK = 16383
}

struct DBusThreadFunctions
{
    uint mask;
    DBusMutexNewFunction mutex_new;
    DBusMutexFreeFunction mutex_free;
    DBusMutexLockFunction mutex_lock;
    DBusMutexUnlockFunction mutex_unlock;
    DBusCondVarNewFunction condvar_new;
    DBusCondVarFreeFunction condvar_free;
    DBusCondVarWaitFunction condvar_wait;
    DBusCondVarWaitTimeoutFunction condvar_wait_timeout;
    DBusCondVarWakeOneFunction condvar_wake_one;
    DBusCondVarWakeAllFunction condvar_wake_all;
    DBusRecursiveMutexNewFunction recursive_mutex_new;
    DBusRecursiveMutexFreeFunction recursive_mutex_free;
    DBusRecursiveMutexLockFunction recursive_mutex_lock;
    DBusRecursiveMutexUnlockFunction recursive_mutex_unlock;
    void function () padding1;
    void function () padding2;
    void function () padding3;
    void function () padding4;
}

struct DBusCondVar;


struct DBusMutex;


dbus_bool_t dbus_threads_init (const(DBusThreadFunctions)* functions);
dbus_bool_t dbus_threads_init_default ();
// END dbus/dbus-threads.d
// START dbus/dbus-message.d
struct DBusMessageIter
{
    void* dummy1;
    void* dummy2;
    dbus_uint32_t dummy3;
    int dummy4;
    int dummy5;
    int dummy6;
    int dummy7;
    int dummy8;
    int dummy9;
    int dummy10;
    int dummy11;
    int pad1;
    int pad2;
    void* pad3;
}

struct DBusMessage;


DBusMessage* dbus_message_new (int message_type);
DBusMessage* dbus_message_new_method_call (const(char)* bus_name, const(char)* path, const(char)* iface, const(char)* method);
DBusMessage* dbus_message_new_method_return (DBusMessage* method_call);
DBusMessage* dbus_message_new_signal (const(char)* path, const(char)* iface, const(char)* name);
DBusMessage* dbus_message_new_error (DBusMessage* reply_to, const(char)* error_name, const(char)* error_message);
DBusMessage* dbus_message_new_error_printf (DBusMessage* reply_to, const(char)* error_name, const(char)* error_format, ...);
DBusMessage* dbus_message_copy (const(DBusMessage)* message);
DBusMessage* dbus_message_ref (DBusMessage* message);
void dbus_message_unref (DBusMessage* message);
int dbus_message_get_type (DBusMessage* message);
dbus_bool_t dbus_message_set_path (DBusMessage* message, const(char)* object_path);
const(char)* dbus_message_get_path (DBusMessage* message);
dbus_bool_t dbus_message_has_path (DBusMessage* message, const(char)* object_path);
dbus_bool_t dbus_message_set_interface (DBusMessage* message, const(char)* iface);
const(char)* dbus_message_get_interface (DBusMessage* message);
dbus_bool_t dbus_message_has_interface (DBusMessage* message, const(char)* iface);
dbus_bool_t dbus_message_set_member (DBusMessage* message, const(char)* member);
const(char)* dbus_message_get_member (DBusMessage* message);
dbus_bool_t dbus_message_has_member (DBusMessage* message, const(char)* member);
dbus_bool_t dbus_message_set_error_name (DBusMessage* message, const(char)* name);
const(char)* dbus_message_get_error_name (DBusMessage* message);
dbus_bool_t dbus_message_set_destination (DBusMessage* message, const(char)* destination);
const(char)* dbus_message_get_destination (DBusMessage* message);
dbus_bool_t dbus_message_set_sender (DBusMessage* message, const(char)* sender);
const(char)* dbus_message_get_sender (DBusMessage* message);
const(char)* dbus_message_get_signature (DBusMessage* message);
void dbus_message_set_no_reply (DBusMessage* message, dbus_bool_t no_reply);
dbus_bool_t dbus_message_get_no_reply (DBusMessage* message);
dbus_bool_t dbus_message_is_method_call (DBusMessage* message, const(char)* iface, const(char)* method);
dbus_bool_t dbus_message_is_signal (DBusMessage* message, const(char)* iface, const(char)* signal_name);
dbus_bool_t dbus_message_is_error (DBusMessage* message, const(char)* error_name);
dbus_bool_t dbus_message_has_destination (DBusMessage* message, const(char)* bus_name);
dbus_bool_t dbus_message_has_sender (DBusMessage* message, const(char)* unique_bus_name);
dbus_bool_t dbus_message_has_signature (DBusMessage* message, const(char)* signature);
dbus_uint32_t dbus_message_get_serial (DBusMessage* message);
void dbus_message_set_serial (DBusMessage* message, dbus_uint32_t serial);
dbus_bool_t dbus_message_set_reply_serial (DBusMessage* message, dbus_uint32_t reply_serial);
dbus_uint32_t dbus_message_get_reply_serial (DBusMessage* message);
void dbus_message_set_auto_start (DBusMessage* message, dbus_bool_t auto_start);
dbus_bool_t dbus_message_get_auto_start (DBusMessage* message);
dbus_bool_t dbus_message_get_path_decomposed (DBusMessage* message, char*** path);
dbus_bool_t dbus_message_append_args (DBusMessage* message, int first_arg_type, ...);
dbus_bool_t dbus_message_append_args_valist (DBusMessage* message, int first_arg_type, va_list var_args);
dbus_bool_t dbus_message_get_args (DBusMessage* message, DBusError* error, int first_arg_type, ...);
dbus_bool_t dbus_message_get_args_valist (DBusMessage* message, DBusError* error, int first_arg_type, va_list var_args);
dbus_bool_t dbus_message_contains_unix_fds (DBusMessage* message);
dbus_bool_t dbus_message_iter_init (DBusMessage* message, DBusMessageIter* iter);
dbus_bool_t dbus_message_iter_has_next (DBusMessageIter* iter);
dbus_bool_t dbus_message_iter_next (DBusMessageIter* iter);
char* dbus_message_iter_get_signature (DBusMessageIter* iter);
int dbus_message_iter_get_arg_type (DBusMessageIter* iter);
int dbus_message_iter_get_element_type (DBusMessageIter* iter);
void dbus_message_iter_recurse (DBusMessageIter* iter, DBusMessageIter* sub);
void dbus_message_iter_get_basic (DBusMessageIter* iter, void* value);
int dbus_message_iter_get_array_len (DBusMessageIter* iter);
void dbus_message_iter_get_fixed_array (DBusMessageIter* iter, void* value, int* n_elements);
void dbus_message_iter_init_append (DBusMessage* message, DBusMessageIter* iter);
dbus_bool_t dbus_message_iter_append_basic (DBusMessageIter* iter, int type, const(void)* value);
dbus_bool_t dbus_message_iter_append_fixed_array (DBusMessageIter* iter, int element_type, const(void)* value, int n_elements);
dbus_bool_t dbus_message_iter_open_container (DBusMessageIter* iter, int type, const(char)* contained_signature, DBusMessageIter* sub);
dbus_bool_t dbus_message_iter_close_container (DBusMessageIter* iter, DBusMessageIter* sub);
void dbus_message_iter_abandon_container (DBusMessageIter* iter, DBusMessageIter* sub);
void dbus_message_lock (DBusMessage* message);
dbus_bool_t dbus_set_error_from_message (DBusError* error, DBusMessage* message);
dbus_bool_t dbus_message_allocate_data_slot (dbus_int32_t* slot_p);
void dbus_message_free_data_slot (dbus_int32_t* slot_p);
dbus_bool_t dbus_message_set_data (DBusMessage* message, dbus_int32_t slot, void* data, DBusFreeFunction free_data_func);
void* dbus_message_get_data (DBusMessage* message, dbus_int32_t slot);
int dbus_message_type_from_string (const(char)* type_str);
const(char)* dbus_message_type_to_string (int type);
dbus_bool_t dbus_message_marshal (DBusMessage* msg, char** marshalled_data_p, int* len_p);
DBusMessage* dbus_message_demarshal (const(char)* str, int len, DBusError* error);
int dbus_message_demarshal_bytes_needed (const(char)* str, int len);
// END dbus/dbus-message.d
// START dbus/dbus-connection.d
alias uint function (DBusWatch*, void*) DBusAddWatchFunction;
alias void function (DBusWatch*, void*) DBusWatchToggledFunction;
alias void function (DBusWatch*, void*) DBusRemoveWatchFunction;
alias uint function (DBusTimeout*, void*) DBusAddTimeoutFunction;
alias void function (DBusTimeout*, void*) DBusTimeoutToggledFunction;
alias void function (DBusTimeout*, void*) DBusRemoveTimeoutFunction;
alias void function (DBusConnection*, DBusDispatchStatus, void*) DBusDispatchStatusFunction;
alias void function (void*) DBusWakeupMainFunction;
alias uint function (DBusConnection*, c_ulong, void*) DBusAllowUnixUserFunction;
alias uint function (DBusConnection*, const(char)*, void*) DBusAllowWindowsUserFunction;
alias void function (DBusPendingCall*, void*) DBusPendingCallNotifyFunction;
alias DBusHandlerResult function (DBusConnection*, DBusMessage*, void*) DBusHandleMessageFunction;
alias void function (DBusConnection*, void*) DBusObjectPathUnregisterFunction;
alias DBusHandlerResult function (DBusConnection*, DBusMessage*, void*) DBusObjectPathMessageFunction;

enum DBusWatchFlags
{
    DBUS_WATCH_READABLE = 1,
    DBUS_WATCH_WRITABLE = 2,
    DBUS_WATCH_ERROR = 4,
    DBUS_WATCH_HANGUP = 8
}

enum DBusDispatchStatus
{
    DBUS_DISPATCH_DATA_REMAINS = 0,
    DBUS_DISPATCH_COMPLETE = 1,
    DBUS_DISPATCH_NEED_MEMORY = 2
}

struct DBusObjectPathVTable
{
    DBusObjectPathUnregisterFunction unregister_function;
    DBusObjectPathMessageFunction message_function;
    void function (void*) dbus_internal_pad1;
    void function (void*) dbus_internal_pad2;
    void function (void*) dbus_internal_pad3;
    void function (void*) dbus_internal_pad4;
}

struct DBusPreallocatedSend;


struct DBusTimeout;


struct DBusPendingCall;


struct DBusConnection;


struct DBusWatch;


DBusConnection* dbus_connection_open (const(char)* address, DBusError* error);
DBusConnection* dbus_connection_open_private (const(char)* address, DBusError* error);
DBusConnection* dbus_connection_ref (DBusConnection* connection);
void dbus_connection_unref (DBusConnection* connection);
void dbus_connection_close (DBusConnection* connection);
dbus_bool_t dbus_connection_get_is_connected (DBusConnection* connection);
dbus_bool_t dbus_connection_get_is_authenticated (DBusConnection* connection);
dbus_bool_t dbus_connection_get_is_anonymous (DBusConnection* connection);
char* dbus_connection_get_server_id (DBusConnection* connection);
dbus_bool_t dbus_connection_can_send_type (DBusConnection* connection, int type);
void dbus_connection_set_exit_on_disconnect (DBusConnection* connection, dbus_bool_t exit_on_disconnect);
void dbus_connection_flush (DBusConnection* connection);
dbus_bool_t dbus_connection_read_write_dispatch (DBusConnection* connection, int timeout_milliseconds);
dbus_bool_t dbus_connection_read_write (DBusConnection* connection, int timeout_milliseconds);
DBusMessage* dbus_connection_borrow_message (DBusConnection* connection);
void dbus_connection_return_message (DBusConnection* connection, DBusMessage* message);
void dbus_connection_steal_borrowed_message (DBusConnection* connection, DBusMessage* message);
DBusMessage* dbus_connection_pop_message (DBusConnection* connection);
DBusDispatchStatus dbus_connection_get_dispatch_status (DBusConnection* connection);
DBusDispatchStatus dbus_connection_dispatch (DBusConnection* connection);
dbus_bool_t dbus_connection_has_messages_to_send (DBusConnection* connection);
dbus_bool_t dbus_connection_send (DBusConnection* connection, DBusMessage* message, dbus_uint32_t* client_serial);
dbus_bool_t dbus_connection_send_with_reply (DBusConnection* connection, DBusMessage* message, DBusPendingCall** pending_return, int timeout_milliseconds);
DBusMessage* dbus_connection_send_with_reply_and_block (DBusConnection* connection, DBusMessage* message, int timeout_milliseconds, DBusError* error);
dbus_bool_t dbus_connection_set_watch_functions (DBusConnection* connection, DBusAddWatchFunction add_function, DBusRemoveWatchFunction remove_function, DBusWatchToggledFunction toggled_function, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_connection_set_timeout_functions (DBusConnection* connection, DBusAddTimeoutFunction add_function, DBusRemoveTimeoutFunction remove_function, DBusTimeoutToggledFunction toggled_function, void* data, DBusFreeFunction free_data_function);
void dbus_connection_set_wakeup_main_function (DBusConnection* connection, DBusWakeupMainFunction wakeup_main_function, void* data, DBusFreeFunction free_data_function);
void dbus_connection_set_dispatch_status_function (DBusConnection* connection, DBusDispatchStatusFunction function_, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_connection_get_unix_user (DBusConnection* connection, c_ulong* uid);
dbus_bool_t dbus_connection_get_unix_process_id (DBusConnection* connection, c_ulong* pid);
dbus_bool_t dbus_connection_get_adt_audit_session_data (DBusConnection* connection, void** data, dbus_int32_t* data_size);
void dbus_connection_set_unix_user_function (DBusConnection* connection, DBusAllowUnixUserFunction function_, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_connection_get_windows_user (DBusConnection* connection, char** windows_sid_p);
void dbus_connection_set_windows_user_function (DBusConnection* connection, DBusAllowWindowsUserFunction function_, void* data, DBusFreeFunction free_data_function);
void dbus_connection_set_allow_anonymous (DBusConnection* connection, dbus_bool_t value);
void dbus_connection_set_route_peer_messages (DBusConnection* connection, dbus_bool_t value);
dbus_bool_t dbus_connection_add_filter (DBusConnection* connection, DBusHandleMessageFunction function_, void* user_data, DBusFreeFunction free_data_function);
void dbus_connection_remove_filter (DBusConnection* connection, DBusHandleMessageFunction function_, void* user_data);
dbus_bool_t dbus_connection_allocate_data_slot (dbus_int32_t* slot_p);
void dbus_connection_free_data_slot (dbus_int32_t* slot_p);
dbus_bool_t dbus_connection_set_data (DBusConnection* connection, dbus_int32_t slot, void* data, DBusFreeFunction free_data_func);
void* dbus_connection_get_data (DBusConnection* connection, dbus_int32_t slot);
void dbus_connection_set_change_sigpipe (dbus_bool_t will_modify_sigpipe);
void dbus_connection_set_max_message_size (DBusConnection* connection, c_long size);
c_long dbus_connection_get_max_message_size (DBusConnection* connection);
void dbus_connection_set_max_received_size (DBusConnection* connection, c_long size);
c_long dbus_connection_get_max_received_size (DBusConnection* connection);
void dbus_connection_set_max_message_unix_fds (DBusConnection* connection, c_long n);
c_long dbus_connection_get_max_message_unix_fds (DBusConnection* connection);
void dbus_connection_set_max_received_unix_fds (DBusConnection* connection, c_long n);
c_long dbus_connection_get_max_received_unix_fds (DBusConnection* connection);
c_long dbus_connection_get_outgoing_size (DBusConnection* connection);
c_long dbus_connection_get_outgoing_unix_fds (DBusConnection* connection);
DBusPreallocatedSend* dbus_connection_preallocate_send (DBusConnection* connection);
void dbus_connection_free_preallocated_send (DBusConnection* connection, DBusPreallocatedSend* preallocated);
void dbus_connection_send_preallocated (DBusConnection* connection, DBusPreallocatedSend* preallocated, DBusMessage* message, dbus_uint32_t* client_serial);
dbus_bool_t dbus_connection_try_register_object_path (DBusConnection* connection, const(char)* path, const(DBusObjectPathVTable)* vtable, void* user_data, DBusError* error);
dbus_bool_t dbus_connection_register_object_path (DBusConnection* connection, const(char)* path, const(DBusObjectPathVTable)* vtable, void* user_data);
dbus_bool_t dbus_connection_try_register_fallback (DBusConnection* connection, const(char)* path, const(DBusObjectPathVTable)* vtable, void* user_data, DBusError* error);
dbus_bool_t dbus_connection_register_fallback (DBusConnection* connection, const(char)* path, const(DBusObjectPathVTable)* vtable, void* user_data);
dbus_bool_t dbus_connection_unregister_object_path (DBusConnection* connection, const(char)* path);
dbus_bool_t dbus_connection_get_object_path_data (DBusConnection* connection, const(char)* path, void** data_p);
dbus_bool_t dbus_connection_list_registered (DBusConnection* connection, const(char)* parent_path, char*** child_entries);
dbus_bool_t dbus_connection_get_unix_fd (DBusConnection* connection, int* fd);
dbus_bool_t dbus_connection_get_socket (DBusConnection* connection, int* fd);
int dbus_watch_get_fd (DBusWatch* watch);
int dbus_watch_get_unix_fd (DBusWatch* watch);
int dbus_watch_get_socket (DBusWatch* watch);
uint dbus_watch_get_flags (DBusWatch* watch);
void* dbus_watch_get_data (DBusWatch* watch);
void dbus_watch_set_data (DBusWatch* watch, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_watch_handle (DBusWatch* watch, uint flags);
dbus_bool_t dbus_watch_get_enabled (DBusWatch* watch);
int dbus_timeout_get_interval (DBusTimeout* timeout);
void* dbus_timeout_get_data (DBusTimeout* timeout);
void dbus_timeout_set_data (DBusTimeout* timeout, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_timeout_handle (DBusTimeout* timeout);
dbus_bool_t dbus_timeout_get_enabled (DBusTimeout* timeout);
// END dbus/dbus-connection.d
// START dbus/dbus-pending-call.d
DBusPendingCall* dbus_pending_call_ref (DBusPendingCall* pending);
void dbus_pending_call_unref (DBusPendingCall* pending);
dbus_bool_t dbus_pending_call_set_notify (DBusPendingCall* pending, DBusPendingCallNotifyFunction function_, void* user_data, DBusFreeFunction free_user_data);
void dbus_pending_call_cancel (DBusPendingCall* pending);
dbus_bool_t dbus_pending_call_get_completed (DBusPendingCall* pending);
DBusMessage* dbus_pending_call_steal_reply (DBusPendingCall* pending);
void dbus_pending_call_block (DBusPendingCall* pending);
dbus_bool_t dbus_pending_call_allocate_data_slot (dbus_int32_t* slot_p);
void dbus_pending_call_free_data_slot (dbus_int32_t* slot_p);
dbus_bool_t dbus_pending_call_set_data (DBusPendingCall* pending, dbus_int32_t slot, void* data, DBusFreeFunction free_data_func);
void* dbus_pending_call_get_data (DBusPendingCall* pending, dbus_int32_t slot);
// END dbus/dbus-pending-call.d
// START dbus/dbus-server.d
alias void function (DBusServer*, DBusConnection*, void*) DBusNewConnectionFunction;

struct DBusServer;


DBusServer* dbus_server_listen (const(char)* address, DBusError* error);
DBusServer* dbus_server_ref (DBusServer* server);
void dbus_server_unref (DBusServer* server);
void dbus_server_disconnect (DBusServer* server);
dbus_bool_t dbus_server_get_is_connected (DBusServer* server);
char* dbus_server_get_address (DBusServer* server);
char* dbus_server_get_id (DBusServer* server);
void dbus_server_set_new_connection_function (DBusServer* server, DBusNewConnectionFunction function_, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_server_set_watch_functions (DBusServer* server, DBusAddWatchFunction add_function, DBusRemoveWatchFunction remove_function, DBusWatchToggledFunction toggled_function, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_server_set_timeout_functions (DBusServer* server, DBusAddTimeoutFunction add_function, DBusRemoveTimeoutFunction remove_function, DBusTimeoutToggledFunction toggled_function, void* data, DBusFreeFunction free_data_function);
dbus_bool_t dbus_server_set_auth_mechanisms (DBusServer* server, const(char*)* mechanisms);
dbus_bool_t dbus_server_allocate_data_slot (dbus_int32_t* slot_p);
void dbus_server_free_data_slot (dbus_int32_t* slot_p);
dbus_bool_t dbus_server_set_data (DBusServer* server, int slot, void* data, DBusFreeFunction free_data_func);
void* dbus_server_get_data (DBusServer* server, int slot);
// END dbus/dbus-server.d
// START dbus/dbus-bus.d
DBusConnection* dbus_bus_get (DBusBusType type, DBusError* error);
DBusConnection* dbus_bus_get_private (DBusBusType type, DBusError* error);
dbus_bool_t dbus_bus_register (DBusConnection* connection, DBusError* error);
dbus_bool_t dbus_bus_set_unique_name (DBusConnection* connection, const(char)* unique_name);
const(char)* dbus_bus_get_unique_name (DBusConnection* connection);
c_ulong dbus_bus_get_unix_user (DBusConnection* connection, const(char)* name, DBusError* error);
char* dbus_bus_get_id (DBusConnection* connection, DBusError* error);
int dbus_bus_request_name (DBusConnection* connection, const(char)* name, uint flags, DBusError* error);
int dbus_bus_release_name (DBusConnection* connection, const(char)* name, DBusError* error);
dbus_bool_t dbus_bus_name_has_owner (DBusConnection* connection, const(char)* name, DBusError* error);
dbus_bool_t dbus_bus_start_service_by_name (DBusConnection* connection, const(char)* name, dbus_uint32_t flags, dbus_uint32_t* reply, DBusError* error);
void dbus_bus_add_match (DBusConnection* connection, const(char)* rule, DBusError* error);
void dbus_bus_remove_match (DBusConnection* connection, const(char)* rule, DBusError* error);
// END dbus/dbus-bus.d
// START dbus/dbus.d

// END dbus/dbus.d
}


enum BusService = "org.freedesktop.DBus";
enum BusPath = "/org/freedesktop/DBus";
enum BusInterface = "org.freedesktop.DBus";

enum NameFlags {
  AllowReplace = 1, ReplaceExisting = 2, NoQueue = 4
}

/// Requests a DBus well-known name.
/// returns if the name is owned after the call.
/// Involves blocking call on a DBus method, may throw an exception on failure.
bool requestName(Connection conn, string name,
                 NameFlags flags = NameFlags.NoQueue | NameFlags.AllowReplace) {
  auto msg = Message(BusService,BusPath,BusInterface,"RequestName");
  msg.build(name,cast(uint)(flags));
  auto res = conn.sendWithReplyBlocking(msg).to!uint;
  return (res == 1) || (res == 4);
}

/// A simple main loop that isn't necessarily efficient
/// and isn't guaranteed to work with other tasks and threads.
/// Use only for apps that only do DBus triggered things.
void simpleMainLoop(Connection conn) {
  while(dbus_connection_read_write_dispatch(conn.conn, -1)) {} // empty loop body
}

/// Single tick in the DBus connection which can be used for
/// concurrent updates.
bool tick(Connection conn) {
  return cast(bool) dbus_connection_read_write_dispatch(conn.conn, 0);
}


