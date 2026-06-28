import json, struct, sys

path = sys.argv[1]
with open(path, 'rb') as f:
    f.read(12)  # magic + version + length
    chunk_length = struct.unpack('<I', f.read(4))[0]
    f.read(4)  # chunk type
    json_data = json.loads(f.read(chunk_length).decode('utf-8'))

    nodes = json_data.get('nodes', [])
    for i, n in enumerate(nodes):
        name = n.get('name', f'node_{i}')
        translation = n.get('translation', [0,0,0])
        rotation = n.get('rotation', [0,0,0,1])
        scale = n.get('scale', [1,1,1])
        mesh = n.get('mesh', -1)
        print(f'{i}: name={name} T={translation} R={rotation} S={scale} mesh={mesh}')

    # Also print accessors to find bounding box info
    if 'accessors' in json_data:
        for i, a in enumerate(json_data['accessors']):
            t = a.get('type', '')
            if 'POSITION' in str(a.get('_name', '')):
                print(f'Accessor {i}: type={t} min={a.get("min","")} max={a.get("max","")}')
