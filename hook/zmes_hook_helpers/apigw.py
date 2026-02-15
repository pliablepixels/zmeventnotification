import zmes_hook_helpers.common_params as g


class ObjectRemote:
    def __init__(self):
        
        class_file_abs_path = g.config['object_labels']
        f = open(class_file_abs_path, 'r')
        self.classes = [line.strip() for line in f.readlines()]

    def set_classes(self, classes):
        self.classes = classes

    def get_classes(self):
        return self.classes


class FaceRemote:
    def __init__(self):
        self.classes = []

    def set_classes(self, classes):
        self.classes = classes

    def get_classes(self):
        return self.classes


class AlprRemote:
    def __init__(self):
        self.classes = []

    def set_classes(self, classes):
        self.classes = classes

    def get_classes(self):
        return self.classes