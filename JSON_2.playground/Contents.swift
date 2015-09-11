import Foundation

protocol Deserializeable {
    static func decode(input: AnyObject) throws -> Self
}

enum SchemeMismatchError {
    case BadContainer
    case KeyMissing
    case OutOfRange(countOfItems: Int)
    case UnexpectedType(expectedTypeName: String)
    
    func toDecodingError() -> DecodingError {
        return DecodingError(error: self, path: [])
    }
}

struct DecodingError: ErrorType, CustomStringConvertible {
    let error: SchemeMismatchError
    let path: [String]
    
    func errorByAppendingPathComponent(component: String) -> DecodingError {
        return DecodingError(error: error, path: [component] + path)
    }
    
    var description: String {
        let pathString = path.joinWithSeparator(".")
        return "\(error) in \(pathString)"
    }
}

//: Array and dictionary helpers

private func appendPathComponentToError<T>(@autoclosure f: () throws -> T, component: String) throws -> T {
    do {
        return try f()
    } catch let error as DecodingError {
        throw error.errorByAppendingPathComponent(component)
    }
}


struct Decoder {
    private let dict: [String: AnyObject]
    init(_ value: AnyObject) throws {
        guard let dict = value as? [String: AnyObject] else { throw SchemeMismatchError.BadContainer.toDecodingError() }
        self.dict = dict
    }
    
    func decode<T: Deserializeable>(forKey key: String) throws -> T {
        return try appendPathComponentToError(T.decode(self.resultForKey(key)), component: key)
    }

    func decode<T: Deserializeable>(forKey key: String) throws -> T? {
        return try appendPathComponentToError(self.optionalForKey(key).map(T.decode), component: key)
    }

    func decode<T: Deserializeable>(forKey key: String) throws -> [T] {
        return try appendPathComponentToError(ArrayDecoder(self.resultForKey(key)).decode(), component: key)
    }
    
    private func resultForKey(key: String) throws -> AnyObject {
        guard let value = dict[key] else { throw SchemeMismatchError.KeyMissing.toDecodingError() }
        return value
    }
    
    private func optionalForKey(key: String) -> AnyObject? {
        return dict[key]
    }
}

struct ArrayDecoder {
    private let array: [AnyObject]
    init(_ value: AnyObject) throws {
        guard let array = value as? [AnyObject] else { throw SchemeMismatchError.BadContainer.toDecodingError() }
        self.array = array
    }

    private func decode<T: Deserializeable>() throws -> [T] {
        var result = [T]()
        for (index, value) in array.enumerate() {
            try appendPathComponentToError(result.append(T.decode(value)), component: String(index))
        }
        return result
    }

    private func resultForIndex(index: Int) throws -> AnyObject {
        guard self.array.count > index && index >= 0 else { throw SchemeMismatchError.OutOfRange(countOfItems: self.array.count).toDecodingError() }
        return self.array[index]
    }

    func decodeJSON<T: Deserializeable>(atIndex index: Int) throws -> T {
        return try appendPathComponentToError(T.decode(self.resultForIndex(index)), component: String(index))
    }
}

//: Types declaration

struct NamedValue<ValueType : Deserializeable, Tag> : Deserializeable {
    let value: ValueType
    func unwrap() -> NamedValue<ValueType, Tag> {
        return self
    }
}

typealias NamedInt = NamedValue<Int, Int>
typealias NamedString = NamedValue<String, String>

struct LeafObject {
    let BunchOfInts: [NamedInt]
    let optionalString: NamedString?
    let someDouble: Double
}

struct RootObject {
    let leaves: [LeafObject]
}

//: Atomic types deserialization
protocol ScalarDeserializeable : Deserializeable {}
extension ScalarDeserializeable {
    static func decode(input: AnyObject) throws -> Self {
        guard let value = input as? Self else { throw SchemeMismatchError.UnexpectedType(expectedTypeName: "\(self)").toDecodingError() }
        return value
    }
}

extension Double : ScalarDeserializeable {}
extension Int : ScalarDeserializeable {}
extension String : ScalarDeserializeable {}

extension NamedValue {
    static func decode(input: AnyObject) throws -> NamedValue<ValueType, Tag> {
        return try NamedValue(value: ValueType.decode(input))
    }
}

//: Composite types  deserialization

extension LeafObject : Deserializeable {
    static func decode(input: AnyObject) throws -> LeafObject {
        let dict = try Decoder(input)
        return try LeafObject(
            BunchOfInts: dict.decode(forKey: "ints"),
            optionalString: dict.decode(forKey: "string"),
            someDouble: dict.decode(forKey: "double")
        )
    }
}

extension RootObject : Deserializeable {
    static func decode(input: AnyObject) throws -> RootObject {
        let dict = try Decoder(input)
        return try RootObject(leaves: dict.decode(forKey: "childs"))
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
do {
    let a = try RootObject.decode(dict)
} catch {
    print(error)
}

