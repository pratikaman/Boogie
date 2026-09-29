"""Bake licensed human models to transparent PNG frames with Blender 4.5.

blender -b -t 6 --python tools/characters/render.py -- \
  --source /path/to/person.fbx --output /tmp/person-frames --id manuel
Raw source models stay outside the repository. See assets/CHARACTERS.md.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--id', required=True, choices=['sophia', 'manuel'])
parser.add_argument('--preview', action='store_true')
parser.add_argument('--motion-source')
parser.add_argument('--reactions-only', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
if args.source.lower().endswith('.glb'):
    bpy.ops.import_scene.gltf(filepath=args.source)
else:
    bpy.ops.import_scene.fbx(filepath=args.source)
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
action = max(bpy.data.actions, key=lambda a: a.frame_range[1])
rig.animation_data_create()
for track in rig.animation_data.nla_tracks:
    track.mute = True
rig.animation_data.action = action
if action.slots:
    rig.animation_data.action_slot = action.slots[0]
first, last = action.frame_range
scene.frame_set(int(first))

# FBX paths are author-machine paths; resolve texture files beside the download.
if not args.source.lower().endswith('.glb'):
    tex = Path(args.source).parent / 'tex'
    for mat in bpy.data.materials:
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        output = nodes.new('ShaderNodeOutputMaterial')
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        bsdf.inputs['Roughness'].default_value = 0.72
        image = nodes.new('ShaderNodeTexImage')
        image.image = bpy.data.images.load(str(next(tex.glob('*_dif.jpg'))))
        mat.node_tree.links.new(image.outputs['Color'], bsdf.inputs['Base Color'])
        mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

meshes = [o for o in scene.objects if o.type == 'MESH']
def bounds():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    points = [o.matrix_world @ Vector(v) for base in meshes for o in [base.evaluated_get(dg)] for v in o.bound_box]
    return Vector(tuple(min(v[i] for v in points) for i in range(3))), Vector(tuple(max(v[i] for v in points) for i in range(3)))
lo, hi = bounds()
height = hi.z - lo.z
roots = [o for o in list(scene.objects) if o.parent is None]
anchor = bpy.data.objects.new('Boogie framing', None)
scene.collection.objects.link(anchor)
for obj in roots:
    obj.parent = anchor
scale = 1.75 / height
anchor.scale = (scale,) * 3
anchor.location = (-(lo.x + hi.x) / 2 * scale, -(lo.y + hi.y) / 2 * scale, -lo.z * scale)

scene.render.engine = 'CYCLES'
scene.cycles.samples = 16
scene.render.use_persistent_data = True
scene.cycles.use_denoising = True
# Metal is available on Apple Silicon; fall back to CPU on other build machines.
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'METAL'
    if any(d.use for d in prefs.devices):
        scene.cycles.device = 'GPU'
except Exception:
    pass
scene.render.resolution_x = 384
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.view_settings.view_transform = 'AgX'
scene.world = bpy.data.worlds.new('Soft studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (0.78, 0.81, 0.86, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = 0.45

def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

def light(name, position, power, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = power, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    point_at(obj, (0, 0, 0.9))

light('Window', (-3, -4, 5), 350, 4, (1.0, 0.91, 0.82))
light('Fill', (3, -2, 2.5), 160, 3, (0.85, 0.9, 1.0))
light('Edge', (1, 2, 4), 250, 3, (1, 0.94, 0.86))
camera = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera'))
scene.collection.objects.link(camera)
camera.location = (0, -6, 0.946)
point_at(camera, (0, 0, 0.946))
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 2.15
scene.camera = camera
fps = 20
source_fps = scene.render.fps
# Both downloads include a calibration T-pose at frame 1. Skip it.
first = 2
count = 240
motion_rig = rig
if args.motion_source:
    previous = set(scene.objects)
    bpy.ops.import_scene.fbx(filepath=args.motion_source)
    imported = set(scene.objects) - previous
    motion_rig = next(o for o in imported if o.type == 'ARMATURE')
    for obj in imported:
        if obj.type == 'MESH':
            obj.hide_render = True
    rig.animation_data_clear()

def suffix(name):
    # Renderpeople use the same named human skeleton across these scans.
    return name.split('_dancing_')[-1] if '_dancing_' in name else name.split('_idling_')[-1]
source_bones = {suffix(b.name): b for b in motion_rig.pose.bones}

def source_pose(t):
    scene.frame_set(int(t), subframe=t % 1)
    return {name: bone.matrix_basis.decompose() for name, bone in source_bones.items()}

def set_pose(t, index):
    pose = source_pose(t)
    blend = max(0, (index - (count - 12)) / 12)
    if blend:
        opening = source_pose(first)
        for name, (loc, rotation, scale) in pose.items():
            a, b, c = opening[name]
            pose[name] = (loc.lerp(a, blend), rotation.slerp(b, blend), scale.lerp(c, blend))
    for bone in rig.pose.bones:
        name = suffix(bone.name)
        if name not in pose:
            continue
        loc, rotation, scale = pose[name]
        ratio = bone.bone.length / max(0.0001, source_bones[name].bone.length)
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = rotation
        bone.location = loc * ratio
        bone.scale = scale
    bpy.context.view_layer.update()

print('BAKE', args.id, 'source frames', first, last, 'count', count, 'bounds', list(lo), list(hi), flush=True)
if args.preview:
    count = 1
for index in range(0 if args.reactions_only else count):
    t = first + index * source_fps / fps
    set_pose(t, index)
    scene.render.filepath = str(out / f'{index:04d}.png')
    bpy.ops.render.render(write_still=True)
clips = {'dance': {'start': 0, 'count': count}}
if not args.preview:
    # Bend the knees in world space, keeping shoes level. Freeze the armature
    # before rendering so FBX's keyed hip location cannot overwrite this pose.
    set_pose(first, 0)
    base = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    rig.animation_data_clear()
    ground = bounds()[0].z
    anchor_z = anchor.location.z
    bones = {suffix(b.name): b for b in rig.pose.bones}
    def rotate_world(bone, radians):
        world = rig.matrix_world @ bone.matrix
        pivot = world.translation.copy()
        world = Matrix.Translation(pivot) @ Matrix.Rotation(radians, 4, 'X') @ Matrix.Translation(-pivot) @ world
        bone.matrix = rig.matrix_world.inverted() @ world
        bpy.context.view_layer.update()
    for stage, degrees in enumerate([22, 43, 62], start=1):
        anchor.location.z = anchor_z
        for b in rig.pose.bones:
            b.matrix_basis = base[b.name]
        bpy.context.view_layer.update()
        angle = math.radians(degrees)
        depth = sum((rig.matrix_world.to_3x3() @ (bones[n].tail - bones[n].head)).length
                    for n in ['upperleg_l', 'lowerleg_l']) * (1 - math.cos(angle))
        hip = bones['hip']
        matrix = hip.matrix.copy()
        matrix.translation += rig.matrix_world.inverted().to_3x3() @ Vector((0, 0, -depth))
        hip.matrix = matrix
        bpy.context.view_layer.update()
        for side in ['l', 'r']:
            rotate_world(bones['upperleg_' + side], -angle)
            rotate_world(bones['lowerleg_' + side], 2 * angle)
            rotate_world(bones['foot_' + side], -angle)
        anchor.location.z += ground - bounds()[0].z
        bpy.context.view_layer.update()
        scene.render.filepath = str(out / f'{count + stage - 1:04d}.png')
        bpy.ops.render.render(write_still=True)
        clips['duck' + str(stage)] = {'start': count + stage - 1, 'count': 1}
(out / 'frames.json').write_text(json.dumps({'width': 384, 'height': 512, 'fps': fps,
                                           'clips': clips}, indent=2))
