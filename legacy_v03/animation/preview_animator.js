// Procedural preview animation for separate, named rigid parts of the CR-X9 blockout.
// NOT a skinned character rig. Designed for replacement with Blender-exported GLTF clips.
export function createPreviewAnimator(root) {
  const parts = {};
  root.traverse(o => { if (o.name) parts[o.name] = o; });
  const base = {};
  for (const [name, part] of Object.entries(parts)) base[name] = { x: part.rotation.x, y: part.position.y };
  const modes = { idle:[0,0,0.012], walk:[0.36,0.25,0.04], run:[0.7,0.55,0.08], sprint:[0.94,0.75,0.12], crouch:[0.04,0.04,0], glide:[0,0.8,0.03], grapple:[0,1.2,0.02], gadget_deploy:[0,0.75,0] };
  let mode='idle', time=0;
  function setMode(next) { if(modes[next]) {mode=next;time=0;} }
  function update(dt) {
    time += Math.min(dt,0.05);
    const [leg, arm, bob] = modes[mode];
    const speed=mode==='sprint'?13:mode==='run'?10:mode==='walk'?7:2;
    const swing=Math.sin(time*speed);
    const apply=(name,angle)=>{const p=parts[name];if(p)p.rotation.x=(base[name]?.x||0)+angle;};
    apply('L_thigh', leg*swing);apply('R_thigh',-leg*swing);
    apply('L_shin', Math.max(0,-swing)*leg*.35);apply('R_shin',Math.max(0,swing)*leg*.35);
    apply('L_upper_arm',-arm*swing);apply('R_upper_arm',arm*swing);
    if(mode==='glide'){apply('L_upper_arm',-1.1);apply('R_upper_arm',-1.1)}
    if(mode==='grapple'){apply('R_upper_arm',-1.4)}
    if(mode==='gadget_deploy'){apply('L_forearm',-1.1)}
    const torso=parts.torso;if(torso)torso.position.y=(base.torso?.y||0)+Math.abs(swing)*bob-(mode==='crouch'?.25:0);
    const cape=parts.cape;if(cape)cape.rotation.x=.06+Math.sin(time*4)*.035+(mode==='glide'?.3:0);
  }
  return {setMode,update,get mode(){return mode}};
}
