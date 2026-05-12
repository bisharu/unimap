import json
import glob

for f in glob.glob('e:/minorProject/unimap/assets/geojson/*.geojson'):
    with open(f, 'r') as file:
        data = json.load(file)
    
    print(f'--- {f} ---')
    for feature in data.get('features', []):
        props = feature.get('properties', {})
        name = props.get('name')
        geom = feature.get('geometry')
        if not name or name == 'null':
            if geom:
                coords = geom.get('coordinates', [])
                num_pts = len(coords[0]) if geom.get('type') == 'Polygon' else len(coords)
                print(f"Type: {geom.get('type')}, Points: {num_pts}")
