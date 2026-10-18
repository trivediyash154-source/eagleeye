final _mem = <String, String>{};

String? read(String key) => _mem[key];
void write(String key, String value) => _mem[key] = value;
void delete(String key) => _mem.remove(key);
