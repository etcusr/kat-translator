// Compile after CatProgressMotion.swift and CatLoadingPlay.swift; see generator.
var motion=CatProgressMotion(progress:0.08,now:0)
var play=CatLoadingPlay(now:0,seed:42)
var forward=true, began=0.0, previousTick=0.0
var rows:[[Double]]=[]
for tick in 0...3600 {
 let now=Double(tick)/30
 var next=motion, nextPlay=play
 let wasAtWall=play.trick == .wallKick
 if play.isPosing { began += max(0,now-previousTick) }; previousTick=now
 nextPlay.advance(now:now,position:forward ? motion.position : 1-motion.position,facingRight:forward,stepLength:0.28)
 if play.trick != nil && nextPlay.trick == nil && nextPlay.travel > 0 {
  let landing=min(1,motion.position+nextPlay.travel);next=CatProgressMotion(progress:landing,now:now);began=now-(landing-0.08)/0.08;nextPlay.settleTravel()
 }
 if wasAtWall && nextPlay.trick == nil {
  let landing=CatLoadingPlay.wallLanding(from:motion.position);forward.toggle();next=CatProgressMotion(progress:landing,now:now);began=now-(landing-0.08)/0.08
 }
 let edge=CatLoadingPlay.wallTakeoff(stepLength:0.28)
 if !nextPlay.isPosing { next.advance(progress:min(edge,0.08+(now-began)*0.08),active:true,now:now) }
 if next.position >= edge { nextPlay.beginWallKick(now:now) }
 motion=next;play=nextPlay
 if tick % 15 == 0 {
  let pos=min(1,max(0,(forward ? motion.position : 1-motion.position)+(forward ? play.travel-play.retreat : play.retreat-play.travel)))
  rows.append([Double(tick),pos,forward == (play.turn < 0.5) ? 1 : 0,motion.standing,motion.stride,motion.leap,play.leap,play.crouch,play.rotation,play.turn,play.travel,play.retreat,play.digging,play.retching,play.spill,play.heave])
 }
}
let data=try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted])
print(String(data:data,encoding:.utf8)!)
