from html.parser import HTMLParser


class Node:
    def __init__(self, tag="", attrs=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.children = []
    def text(self):
        return " ".join(x if isinstance(x, str) else x.text() for x in self.children).strip()
    def find(self, cls):
        return next(iter(self.find_all(cls)), None)
    def find_all(self, cls):
        result = [self] if cls in self.attrs.get("class", "").split() else []
        for node in self.children:
            if isinstance(node, Node): result.extend(node.find_all(cls))
        return result
    def tags(self, tag):
        result = [self] if self.tag == tag else []
        for node in self.children:
            if isinstance(node, Node): result.extend(node.tags(tag))
        return result


class Document(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs); self.stack[-1].children.append(node)
        if tag not in {"img", "input", "meta", "link", "br", "hr", "source", "wbr", "area", "base", "embed", "param", "track", "col"}:
            self.stack.append(node)
    def handle_endtag(self, tag):
        for index in range(len(self.stack)-1, 0, -1):
            if self.stack[index].tag == tag:
                self.stack = self.stack[:index]; break
    def handle_data(self, data): self.stack[-1].children.append(data)
