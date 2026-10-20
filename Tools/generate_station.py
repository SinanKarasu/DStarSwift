"""Generate DStar's original docking-core glTF. Metres, +Y station axis. MIT."""
import base64, json, math, pathlib, struct
parts = []
def part(name, color):
    points = []
    parts.append((name, color, points))
    return points
def quad(p, a,b,c,d):
    # Explicit reverse faces keep the hull visible from inside in both backends.
    p.extend([a,b,c,a,c,d,c,b,a,d,c,a])
def box(p, x0,x1,y0,y1,z0,z1):
    v=[(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),
       (x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]
    for a,b,c,d in [(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)]:
        quad(p,v[a],v[b],v[c],v[d])
hull=part('hull', [0.32,0.39,0.48,1])
for i in range(48):
    a,b=[j*math.tau/48 for j in (i,i+1)]
    quad(hull,(15*math.cos(a),-60,15*math.sin(a)),(15*math.cos(b),-60,15*math.sin(b)),
         (15*math.cos(b),60,15*math.sin(b)),(15*math.cos(a),60,15*math.sin(a)))
interior=part('tunnel', [0.17,0.23,0.29,1])
box(interior,-10,-9,-60,60,-6,6); box(interior,9,10,-60,60,-6,6)
box(interior,-9,9,-60,60,-7,-6); box(interior,-9,9,-60,60,6,7)
box(interior,-10,10,59,60,-7,7)
trim=part('entrance', [0.95,0.55,0.12,1])
box(trim,-11,-9,-61,-59,-8,8); box(trim,9,11,-61,-59,-8,8)
box(trim,-9,9,-61,-59,-8,-6); box(trim,-9,9,-61,-59,6,8)
lights=part('guides', [0.15,0.95,1,1])
for y in range(-120,50,10):
    for x in (-8,8): box(lights,x-.18,x+.18,y-.6,y+.6,-5.9,-5.6)
berth=part('berth', [0.2,1,0.4,1])
box(berth,-3,3,37,38,-3.5,-3.2)
box(berth,-.15,.15,38,39,-2,2); box(berth,-2,2,38,39,-.15,.15)
doc={'asset':{'version':'2.0','generator':'DStarSwift docking-core generator'},'scene':0,
     'scenes':[{'nodes':list(range(len(parts)))}], 'nodes':[], 'meshes':[], 'materials':[],
     'accessors':[], 'bufferViews':[], 'buffers':[], 'extensionsUsed':['KHR_materials_unlit']}
binary=bytearray()
for i,(name,color,points) in enumerate(parts):
    data=struct.pack('<'+'f'*len(points)*3,*(v for p in points for v in p))
    doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':len(data),'target':34962})
    binary.extend(data)
    doc['accessors'].append({'bufferView':i,'componentType':5126,'count':len(points),'type':'VEC3',
      'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]})
    doc['materials'].append({'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':color},'extensions':{'KHR_materials_unlit':{}}})
    doc['meshes'].append({'name':name,'primitives':[{'attributes':{'POSITION':i},'material':i,'mode':4}]})
    doc['nodes'].append({'name':name,'mesh':i})
doc['buffers']=[{'byteLength':len(binary),'uri':'data:application/octet-stream;base64,'+base64.b64encode(binary).decode()}]
out=pathlib.Path(__file__).resolve().parents[1]/'DStarSwift/Assets/DockingCore.gltf'
out.write_text(json.dumps(doc,indent=2)+'\n')
print(out)
