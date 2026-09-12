class PartialResult(list):
    """Valid observed items accompanied by a warning, never a full-success claim."""
    def __init__(self, items, warning):
        super().__init__(items)
        self.warning = warning
