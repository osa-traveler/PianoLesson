import Foundation

/// MusicXML を読むための簡単な木構造（XMLParser で組み立てる）
final class XMLElementNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLElementNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLElementNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XMLElementNode] { children.filter { $0.name == name } }
    func string(_ name: String) -> String? {
        child(name).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    func int(_ name: String) -> Int? { string(name).flatMap { Int($0) } }
    func double(_ name: String) -> Double? { string(name).flatMap { Double($0) } }
    func has(_ name: String) -> Bool { child(name) != nil }
    /// パスをたどる（例: "notations/technical/fingering"）
    func descendant(_ path: String) -> XMLElementNode? {
        var node: XMLElementNode? = self
        for part in path.split(separator: "/") { node = node?.child(String(part)) }
        return node
    }

    static func parse(_ data: Data) throws -> XMLElementNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw MusicXMLError.invalidXML(parser.parserError?.localizedDescription ?? "")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLElementNode?
        var stack: [XMLElementNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLElementNode(name: elementName, attributes: attributeDict)
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
