//
//  LinkedList.swift
//  trailer
//
//  Created by Paul Tsochantaris on 07/01/2023.
//

import Foundation

final class LinkedList<Value>: Sequence {
    final class Node<Value> {
        fileprivate let value: Value
        fileprivate var next: Node<Value>?

        init(_ value: Value, _ next: Node<Value>?) {
            self.value = value
            self.next = next
        }
    }

    private var head: Node<Value>?
    private var tail: Node<Value>?

    var count: Int

    init(value: Value? = nil) {
        if let value {
            let newNode = Node(value, nil)
            head = newNode
            tail = newNode
            count = 1
        } else {
            head = nil
            tail = nil
            count = 0
        }
    }

    func push(_ value: Value) {
        count += 1

        let newNode = Node(value, head)
        if tail == nil {
            tail = newNode
        }
        head = newNode
    }
    
    func append(_ value: Value) {
        count += 1

        let newNode = Node(value, nil)
        if let t = tail {
            t.next = newNode
        } else {
            head = newNode
        }
        tail = newNode
    }
    
    func append(contentsOf collection: LinkedList<Value>) {
        if collection.count == 0 {
            return
        }
        
        count += collection.count

        if let t = tail {
            t.next = collection.head
        } else {
            head = collection.head
        }
        tail = collection.tail
    }


    func pop() -> Value? {
        if let top = head {
            head = top.next
            count -= 1
            return top.value
        } else {
            return nil
        }
    }
    
    var first: Value? {
        head?.value
    }

    @discardableResult
    func remove(first removeCheck: (Value) -> Bool) -> Bool {
        guard var prev = head else {
            return false
        }
        
        var current = head
        
        while let c = current {
            if removeCheck(c.value) {
                prev.next = c.next
                count -= 1
                if count == 0 {
                    head = nil
                    tail = nil
                } else if tail === c {
                    tail = prev
                }
                return true
            }
                        
            prev = c
            current = c.next
        }
        
        return false
    }

    func removeAll() {
        head = nil
        tail = nil
        count = 0
    }

    final class ListIterator: IteratorProtocol {
        private var current: Node<Value>?

        fileprivate init(_ current: Node<Value>?) {
            self.current = current
        }

        func next() -> Value? {
            if let res = current {
                current = res.next
                return res.value
            } else {
                return nil
            }
        }
    }

    /// Returns an iterator over the elements of this sequence.
    func makeIterator() -> ListIterator {
        ListIterator(head)
    }

    var underestimatedCount: Int { count }

    func withContiguousStorageIfAvailable<R>(_: (_ buffer: UnsafeBufferPointer<Value>) throws -> R) rethrows -> R? { nil }
}

extension LinkedList: Codable where Value: Codable {
    convenience init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        self.init()
        if let list = try? values.decode([Value].self) {
            for object in list {
                append(object)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(Array(self))
    }
}
