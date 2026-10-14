package org.openoffline.translator.android

import kotlin.math.*

// Direct port of OfflineCore/CatProgressMotion.swift and CatLoadingPlay.swift.
internal class CatMotion(progress:Double,now:Double) {
    enum class Phase { SITTING, RISING, WALKING, JUMPING, SETTLING }
    var phase=Phase.SITTING
    var position=clamp(progress);var standing=0.0;var stride=0.0;var animationTime=0.0;var running=0.0;var leap=0.0
    private var lastTarget=position;private var sampledAt=now;private var rate=0.0;private var began=now
    private var origin=0.0;private var destination=0.0;private var jumpDuration=.35;private var previousTime=now;private var createdAt=now
    fun advance(progress:Double,active:Boolean,now:Double) {
        val target=clamp(progress)
        if(!active || target<lastTarget) {
            phase=Phase.SITTING;position=target;standing=0.0;stride=0.0;animationTime=0.0;running=0.0;leap=0.0
            lastTarget=target;sampledAt=now;rate=0.0;began=now;origin=0.0;destination=0.0;jumpDuration=.35;previousTime=now;createdAt=now;return
        }
        val dt=(now-previousTime).coerceIn(0.0,.1);previousTime=now;animationTime=max(0.0,now-createdAt)
        if(target>lastTarget) { val sample=min(1.0,(target-lastTarget)/max(.033,now-sampledAt));rate=if(rate==0.0)sample else rate*.65+sample*.35;sampledAt=now }
        lastTarget=target;val elapsed=max(0.0,now-began);val gap=max(0.0,target-position)
        when(phase) {
            Phase.SITTING -> if(gap>.00001 && elapsed>=if(rate>.12).06 else .35) { running=clamp((rate-.025)/.16);phase=Phase.RISING;began=now }
            Phase.RISING -> { val duration=if(rate>.12).12 else .24;standing=smooth(elapsed/duration);if(elapsed>=duration) { phase=Phase.WALKING;standing=1.0;began=now } }
            Phase.WALKING -> {
                running=clamp((rate-.025)/.16)
                if(elapsed>.10 && gap>.08 && (rate>.45 || gap>.18)) { origin=position;destination=target;jumpDuration=min(.4,max(.22,gap/max(.6,rate*2)));phase=Phase.JUMPING;began=now }
                else { position=min(target,position+max(.025,rate*1.35+gap*3)*dt);stride=sin(animationTime*PI*2*(1.2+2.8*running));if(target-position<.00001 && now-sampledAt>.18) { stride=0.0;phase=Phase.SETTLING;began=now } }
            }
            Phase.JUMPING -> { val fraction=clamp(elapsed/jumpDuration);position=min(target,origin+(destination-origin)*fraction);leap=sin(fraction*PI);stride=-leap*.7;if(fraction>=1) { position=min(target,destination);leap=0.0;stride=0.0;phase=Phase.WALKING;began=now } }
            Phase.SETTLING -> if(gap>.01) { phase=Phase.RISING;began=now-standing*.12 } else { standing=1-smooth(elapsed/.25);if(elapsed>=.25) { standing=0.0;phase=Phase.SITTING;began=now } }
        }
    }
}
internal fun clamp(value:Double)=if(value.isFinite())value.coerceIn(0.0,1.0) else 0.0
internal fun smooth(value:Double):Double { val t=clamp(value);return t*t*(3-2*t) }
internal class CatPlay(now:Double,seed:Long=kotlin.random.Random.nextLong()) {
    enum class Trick { HOP, DOUBLE_HOP, SOMERSAULT, MISCHIEF, WALL_KICK, PUKE }
    enum class Mark { PILE, PUDDLE }
    var trick:Trick?=null;var leap=0.0;var crouch=0.0;var rotation=0.0;var turn=0.0;var retreat=0.0
    var markKind=Mark.PILE;var markCover=0.0;var travel=0.0;var digging=0.0;var retching=0.0;var spill=0.0;var heave=0.0
    var markPosition:Double?=null;var markFacingRight=true;var markOpacity=0.0
    private var step=.18;private var didLeaveMark=false;private var randomState=seed;private var nextAt=now+delay(3.0,7.0);private var began=0.0;private var markAt:Double?=null
    val isPosing get()=trick in setOf(Trick.MISCHIEF,Trick.WALL_KICK,Trick.PUKE)
    private fun random():Double { randomState=randomState*6364136223846793005L+1442695040888963407L;return (randomState ushr 11).toDouble()/9007199254740992.0 }
    private fun delay(low:Double,high:Double)=low+random()*(high-low)
    fun settleTravel() { travel=0.0 }
    fun beginWallKick(now:Double):Boolean { if(!now.isFinite() || trick!=null)return false;trick=Trick.WALL_KICK;began=now;return true }
    fun advance(now:Double,position:Double,facingRight:Boolean,stepLength:Double=.18) {
        if(!now.isFinite())return
        markAt?.let { val age=now-it;markOpacity=clamp((5-age)/1.3);if(age>=5) { markAt=null;markPosition=null;markOpacity=0.0 } }
        if(trick==null && now>=nextAt) {
            val choice=random();trick=when { choice<.44 -> Trick.HOP;choice<.65 -> Trick.DOUBLE_HOP;choice<.82 -> Trick.SOMERSAULT;choice<.91 -> Trick.MISCHIEF;else -> Trick.PUKE }
            val room=if(facingRight)1-position else position;step=if(stepLength.isFinite())clamp(stepLength) else .18
            if(trick==Trick.PUKE && (step<=0 || room<step))trick=Trick.HOP
            if(trick==Trick.MISCHIEF)step=min(step*.35,max(0.0,room))
            didLeaveMark=false;began=now
        }
        val action=trick ?: return;val elapsed=max(0.0,now-began)
        val duration=when(action) { Trick.HOP->.9;Trick.DOUBLE_HOP->1.7;Trick.SOMERSAULT->1.45;Trick.MISCHIEF->5.2;Trick.PUKE->4.5;Trick.WALL_KICK->.92 }
        val phase=min(1.0,elapsed/duration)
        when(action) {
            Trick.HOP -> leap=sin(PI*phase)
            Trick.DOUBLE_HOP -> leap=abs(sin(PI*2*phase))*(if(phase<.5)1.0 else .75)
            Trick.SOMERSAULT -> { val air=clamp((elapsed-.16)/1.10);leap=sin(PI*air);rotation=360*smooth(air);crouch=if(elapsed<.16)sin(PI*elapsed/.16)*.6 else if(elapsed>1.26)sin(PI*min(1.0,(elapsed-1.26)/.19))*.35 else 0.0 }
            Trick.WALL_KICK -> { val air=clamp((elapsed-.14)/.60);crouch=when { elapsed<.14->smooth(elapsed/.14);elapsed<.22->1-smooth((elapsed-.14)/.08);elapsed>.74->sin(PI*min(1.0,(elapsed-.74)/.18))*.5;else->0.0 };leap=4*air*(1-air);turn=smooth((air-.14)/.48);retreat=.24*(1-(1-air).pow(2));rotation=-sin(PI*air)*22 }
            Trick.MISCHIEF -> {
                crouch=smooth(elapsed/.45)*(1-smooth((elapsed-1.5)/.5))
                if(elapsed>=1.25 && !didLeaveMark)leaveMark(Mark.PILE,now,position,facingRight)
                travel=step*smooth((elapsed-1.8)/.6);digging=if(elapsed>=2.4 && elapsed<4.8)(elapsed-2.4)/2.4 else 0.0;markCover=smooth((elapsed-2.5)/2.3)
                if(elapsed>=4.8) { markPosition=null;markAt=null;markOpacity=0.0 }
            }
            Trick.PUKE -> {
                retching=smooth(elapsed/.30)*(1-smooth((elapsed-2.55)/.35));heave=0.0
                for((start,length) in listOf(.35 to .32,.88 to .34,1.43 to .36))if(elapsed>=start && elapsed<start+length)heave=sin(PI*(elapsed-start)/length).pow(2)
                crouch=retching*.15+heave*.45;spill=if(elapsed>=2.0 && elapsed<2.65)sin(PI*(elapsed-2)/.65) else 0.0
                if(elapsed>=2.15 && !didLeaveMark)leaveMark(Mark.PUDDLE,now,position,facingRight)
                val air=clamp((elapsed-3.1)/1.0);leap=sin(PI*air);travel=step*smooth(air)
            }
        }
        if(elapsed>=duration) { trick=null;leap=0.0;crouch=0.0;rotation=0.0;turn=0.0;retreat=0.0;retching=0.0;spill=0.0;digging=0.0;heave=0.0;nextAt=now+delay(4.5,11.0) }
    }
    private fun leaveMark(kind:Mark,now:Double,position:Double,facingRight:Boolean) { didLeaveMark=true;markAt=now;markOpacity=1.0;markCover=0.0;markKind=kind;markPosition=if(position.isFinite())clamp(position) else .5;markFacingRight=facingRight }
    companion object {
        fun wallTakeoff(stepLength:Double)=1-min(.25,max(.10,if(stepLength.isFinite())stepLength*.55 else .15))
        fun wallLanding(takeoff:Double)=clamp(1-takeoff+.24)
    }
}
/** Same preparation choreography as CatPreparationProgressView, including continuous wall landings. */
internal class CatPreparation(private val seed:Long=kotlin.random.Random.nextLong()) {
    var motion=CatMotion(.08,0.0);var play=CatPlay(0.0,seed);var forward=true
    private var began=0.0;private var previous=0.0
    val position get()=clamp((if(forward)motion.position else 1-motion.position)+(if(forward)play.travel-play.retreat else play.retreat-play.travel))
    val facingRight get()=forward==(play.turn<.5)
    fun advance(now:Double,stepLength:Double) {
        if(now<previous) { motion=CatMotion(.08,now);play=CatPlay(now,seed);forward=true;began=now;previous=now }
        val oldTrick=play.trick;val wasAtWall=oldTrick==CatPlay.Trick.WALL_KICK
        if(play.isPosing)began+=max(0.0,now-previous)
        previous=now;play.advance(now,if(forward)motion.position else 1-motion.position,forward,stepLength)
        if(oldTrick!=null && play.trick==null && play.travel>0) { val landing=min(1.0,motion.position+play.travel);motion=CatMotion(landing,now);began=now-(landing-.08)/.08;play.settleTravel() }
        if(wasAtWall && play.trick==null) { val landing=CatPlay.wallLanding(motion.position);forward=!forward;motion=CatMotion(landing,now);began=now-(landing-.08)/.08 }
        val edge=CatPlay.wallTakeoff(stepLength)
        if(!play.isPosing)motion.advance(min(edge,.08+(now-began)*.08),true,now)
        if(motion.position>=edge)play.beginWallKick(now)
    }
}
