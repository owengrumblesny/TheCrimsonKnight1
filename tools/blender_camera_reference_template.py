# Execute inside Blender via: blender -b model.blend --python tools/blender_camera_reference_template.py
# ChatGPT template. Requires existing selected canonical 3D subject in scene.
import bpy, math, os
from mathutils import Vector
out=os.environ.get('CK_RENDER_DIR','/tmp/crimson_multiview')
os.makedirs(out,exist_ok=True)
scene=bpy.context.scene
camdata=bpy.data.cameras.new('CK_OrthographicReference')
cam=bpy.data.objects.new('CK_OrthographicReference',camdata)
scene.collection.objects.link(cam);scene.camera=cam
camdata.type='ORTHO';camdata.ortho_scale=3.2
scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
# Object assumed centered at origin, Blender Z up, roughly 2 meters high.
target=Vector((0,0,1.0));distance=5.0
for name,angle in [('front',0),('front_left_45',45),('left',90),('rear',180),('right',270),('front_right_45',315)]:
 theta=math.radians(angle)
 cam.location=(math.sin(theta)*distance,-math.cos(theta)*distance,1.1)
 direction=target-cam.location
 cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=os.path.join(out,name+'.png')
 bpy.ops.render.render(write_still=True)
