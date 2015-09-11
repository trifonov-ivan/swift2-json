import Foundation

protocol Deserializeable {
    static func decode(input: AnyObject) -> Self?
}

//: Functional extensions

func curry<A, B, R>(f: (A, B) -> R) -> A -> B -> R {
    return { a in { b in f(a, b) } }
}

func curry<A, B, C, R>(f: (A, B, C) -> R) -> A -> B -> C -> R {
    return { a in { b in {c in f(a, b, c) } } }
}

infix operator >>>= { precedence 150 associativity left }

func >>>= <U,T>(optional: T?, f: T -> U?) -> U? {
    return flatten(optional.map(f))
}

func >>>= <U,T>(value: T, f: T -> U?) -> U? {
    return f(value)
}

func flatten<A>(x: A??) -> A? {
    if let y = x { return y }
    return nil
}

infix operator <*> { associativity left }
func <*><A, B>(f: (A -> B)?, x: A?) -> B? {
    if let f1 = f, x1 = x {
        return f1(x1)
    }
    return nil
}

infix operator <?> { associativity left }
func <?><A, B>(f: (A? -> B)?, x: A?) -> B? {
    if let f1 = f {
        return f1(x)
    }
    return nil
}

//: Array and dictionary deserialization helpers

func asDict(x: AnyObject) -> [String: AnyObject]? {
    return x as? [String: AnyObject]
}

func asArray(x: AnyObject) -> [AnyObject]? {
    return x as? [AnyObject]
}

func objectForKey(key: String)(dict: [String: AnyObject]) -> AnyObject? {
    return dict[key]
}

func decodeArray<T: Deserializeable>(input: [AnyObject]) -> [T]? {
    let result = input.flatMap(T.decode)
    return result.count == input.count ? result : nil
}

//: Types declaration
struct NamedInt {
    let value: Int
}

struct NamedString {
    let value: String
}

struct LeafObject {
    let BunchOfInts: [NamedInt]
    let optionalString: NamedString?
    let someDouble: Double
}

struct RootObject {
    let leaves: [LeafObject]
}


//: Atomic types deserialization
extension Double : Deserializeable {
    static func decode(input: AnyObject) -> Double? {
        return input as? Double
    }
}

extension Int : Deserializeable {
    static func decode(input: AnyObject) -> Int? {
        return input as? Int
    }
}

extension String : Deserializeable {
    static func decode(input: AnyObject) -> String? {
        return input as? String
    }
}

//: Simple composite types deserialization

extension NamedInt : Deserializeable {
    static func decode(input: AnyObject) -> NamedInt? {
        return { NamedInt(value: $0) } <*> Int.decode(input)
    }
}

extension NamedString : Deserializeable {
    static func decode(input: AnyObject) -> NamedString? {
        return { NamedString(value: $0) } <*> String.decode(input)
    }
}

//: Composite types  deserialization

extension LeafObject : Deserializeable {
    static func decode(input: AnyObject) -> LeafObject? {
        let curriedConstructor = curry { LeafObject(BunchOfInts: $0, optionalString: $1, someDouble: $2) }
        let dict = asDict(input)
        return curriedConstructor
            <*> dict >>>= objectForKey("ints") >>>= asArray >>>= decodeArray
            <?> dict >>>= objectForKey("string") >>>= NamedString.decode
            <*> dict >>>= objectForKey("double") >>>= Double.decode
    }
}

extension RootObject : Deserializeable {
    static func decode(input: AnyObject) -> RootObject? {
        let dict = asDict(input)
        return { RootObject(leaves: $0) } <*> (dict >>>= objectForKey("childs") >>>= asArray >>>= decodeArray)
    }
}
//: example

let JSON = ("{\"childs\" :" +
    "[" +
    "{" +
            "\"ints\": [1, 2 ,3]," +
            "\"string\": \"superString\"," +
            "\"double\" : 1.25" +
    "}," +
    "{" +
            "\"ints\": []," +
            "\"double\" : 2.5" +
    "}" +
    "]" +
"}") as AnyObject
//Please, don't use so much of ! in real code - it's just an simple example
let dict = try! NSJSONSerialization.JSONObjectWithData(JSON.dataUsingEncoding(NSUTF8StringEncoding)!, options: NSJSONReadingOptions())

print(RootObject.decode(dict))

/*: trouble: in complex expressions compiler cannot infer types for params. Sometimes compiler stucks, sometime crashes - so in production use needs to add one more wrapping object

    struct DeserializeableArray<T: Deserializeable> {
        func decode(input: AnyObject) -> [T]? {
            return decodeArray(asArray(input))
        }
    }

and parsing becomes like that

    return curriedConstructor
        <*> dict >>>= objectForKey("ints") >>>= DeserializeableArray<NamedInt>.decode
        <?> dict >>>= objectForKey("string") >>>= NamedString.decode
        <*> dict >>>= objectForKey("double") >>>= Double.decode

*/
