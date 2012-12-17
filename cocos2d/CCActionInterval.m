/*
 * cocos2d for iPhone: http://www.cocos2d-iphone.org
 *
 * Copyright (c) 2008-2011 Ricardo Quesada
 * Copyright (c) 2011 Zynga Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */



#import "CCActionInterval.h"
#import "CCActionInstant.h"
#import "CCSprite.h"
#import "CCSpriteFrame.h"
#import "CCAnimation.h"
#import "CCNode.h"
#import "Support/CGPointExtension.h"

//
// IntervalAction
//
#pragma mark - CCIntervalAction
@implementation CCActionInterval

@synthesize elapsed = elapsed_;

-(id) init
{
	NSAssert(NO, @"IntervalActionInit: Init not supported. Use InitWithDuration");
	[self release];
	return nil;
}

+(id) actionWithDuration: (ccTime) d
{
	return [[[self alloc] initWithDuration:d ] autorelease];
}

-(id) initWithDuration: (ccTime) d
{
	if( (self=[super init]) ) {
		_duration = d;

		// prevent division by 0
		// This comparison could be in step:, but it might decrease the performance
		// by 3% in heavy based action games.
		if( _duration == 0 )
			_duration = FLT_EPSILON;
		elapsed_ = 0;
		firstTick_ = YES;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] ];
	return copy;
}

- (BOOL) isDone
{
	return (elapsed_ >= _duration);
}

-(void) step: (ccTime) dt
{
	if( firstTick_ ) {
		firstTick_ = NO;
		elapsed_ = 0;
	} else
		elapsed_ += dt;


	[self update: MAX(0,					// needed for rewind. elapsed could be negative
					  MIN(1, elapsed_/
						  MAX(_duration,FLT_EPSILON)	// division by 0
						  )
					  )
	 ];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	elapsed_ = 0.0f;
	firstTick_ = YES;
}

- (CCActionInterval*) reverse
{
	NSAssert(NO, @"CCIntervalAction: reverse not implemented.");
	return nil;
}
@end

//
// Sequence
//
#pragma mark - CCSequence
@implementation CCSequence
+(id) actions: (CCFiniteTimeAction*) action1, ...
{
	va_list args;
	va_start(args, action1);

	id ret = [self actions:action1 vaList:args];

	va_end(args);

	return  ret;
}

+(id) actions: (CCFiniteTimeAction*) action1 vaList:(va_list)args
{
	CCFiniteTimeAction *now;
	CCFiniteTimeAction *prev = action1;
	
	while( action1 ) {
		now = va_arg(args,CCFiniteTimeAction*);
		if ( now )
			prev = [self actionOne: prev two: now];
		else
			break;
	}

	return prev;
}


+(id) actionWithArray: (NSArray*) actions
{
	CCFiniteTimeAction *prev = [actions objectAtIndex:0];
	
	for (NSUInteger i = 1; i < [actions count]; i++)
		prev = [self actionOne:prev two:[actions objectAtIndex:i]];
	
	return prev;
}

+(id) actionOne: (CCFiniteTimeAction*) one two: (CCFiniteTimeAction*) two
{
	return [[[self alloc] initOne:one two:two ] autorelease];
}

-(id) initOne: (CCFiniteTimeAction*) one two: (CCFiniteTimeAction*) two
{
	NSAssert( one!=nil && two!=nil, @"Sequence: arguments must be non-nil");
	NSAssert( one!=actions_[0] && one!=actions_[1], @"Sequence: re-init using the same parameters is not supported");
	NSAssert( two!=actions_[1] && two!=actions_[0], @"Sequence: re-init using the same parameters is not supported");
	
	ccTime d = [one duration] + [two duration];
	
	if( (self=[super initWithDuration: d]) ) {
		
		// XXX: Supports re-init without leaking. Fails if one==one_ || two==two_
		[actions_[0] release];
		[actions_[1] release];
		
		actions_[0] = [one retain];
		actions_[1] = [two retain];
	}
	
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone:zone] initOne:[[actions_[0] copy] autorelease] two:[[actions_[1] copy] autorelease] ];
	return copy;
}

-(void) dealloc
{
	[actions_[0] release];
	[actions_[1] release];
	[super dealloc];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	split_ = [actions_[0] duration] / MAX(_duration, FLT_EPSILON);
	last_ = -1;
}

-(void) stop
{
	// Issue #1305
	if( last_ != - 1)
		[actions_[last_] stop];

	[super stop];
}

-(void) update: (ccTime) t
{
	int found = 0;
	ccTime new_t = 0.0f;
	
	if( t < split_ ) {
		// action[0]
		found = 0;
		if( split_ != 0 )
			new_t = t / split_;
		else
			new_t = 1;

	} else {
		// action[1]
		found = 1;
		if ( split_ == 1 )
			new_t = 1;
		else
			new_t = (t-split_) / (1 - split_ );
	}
	
	if ( found==1 ) {
		
		if( last_ == -1 ) {
			// action[0] was skipped, execute it.
			[actions_[0] startWithTarget:_target];
			[actions_[0] update:1.0f];
			[actions_[0] stop];
		}
		else if( last_ == 0 )
		{
			// switching to action 1. stop action 0.
			[actions_[0] update: 1.0f];
			[actions_[0] stop];
		}
	}
	
	// Last action found and it is done.
	if( found == last_ && [actions_[found] isDone] ) {
		return;
	}

	// New action. Start it.
	if( found != last_ )
		[actions_[found] startWithTarget:_target];
	
	[actions_[found] update: new_t];
	last_ = found;
}

- (CCActionInterval *) reverse
{
	return [[self class] actionOne: [actions_[1] reverse] two: [actions_[0] reverse ] ];
}
@end

//
// Repeat
//
#pragma mark - CCRepeat
@implementation CCRepeat
@synthesize innerAction=_innerAction;

+(id) actionWithAction:(CCFiniteTimeAction*)action times:(NSUInteger)times
{
	return [[[self alloc] initWithAction:action times:times] autorelease];
}

-(id) initWithAction:(CCFiniteTimeAction*)action times:(NSUInteger)times
{
	ccTime d = [action duration] * times;

	if( (self=[super initWithDuration: d ]) ) {
		times_ = times;
		self.innerAction = action;
		isActionInstant_ = ([action isKindOfClass:[CCActionInstant class]]) ? YES : NO;

		//a instant action needs to be executed one time less in the update method since it uses startWithTarget to execute the action
		if (isActionInstant_) times_ -=1;
		total_ = 0;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone:zone] initWithAction:[[_innerAction copy] autorelease] times:times_];
	return copy;
}

-(void) dealloc
{
	[_innerAction release];
	[super dealloc];
}

-(void) startWithTarget:(id)aTarget
{
	total_ = 0;
	nextDt_ = [_innerAction duration]/_duration;
	[super startWithTarget:aTarget];
	[_innerAction startWithTarget:aTarget];
}

-(void) stop
{
    [_innerAction stop];
	[super stop];
}


// issue #80. Instead of hooking step:, hook update: since it can be called by any
// container action like CCRepeat, CCSequence, CCEase, etc..
-(void) update:(ccTime) dt
{
	if (dt >= nextDt_)
	{
		while (dt > nextDt_ && total_ < times_)
		{

			[_innerAction update:1.0f];
			total_++;

			[_innerAction stop];
			[_innerAction startWithTarget:_target];
			nextDt_ += [_innerAction duration]/_duration;
		}
		
		// fix for issue #1288, incorrect end value of repeat
		if(dt >= 1.0f && total_ < times_) 
		{
			total_++;
		}
		
		// don't set a instantaction back or update it, it has no use because it has no duration
		if (!isActionInstant_)
		{
			if (total_ == times_)
			{
				[_innerAction update:1];
				[_innerAction stop];
			}
			else
			{
				// issue #390 prevent jerk, use right update
				[_innerAction update:dt - (nextDt_ - _innerAction.duration/_duration)];
			}
		}
	}
	else
	{
		[_innerAction update:fmodf(dt * times_,1.0f)];
	}
}

-(BOOL) isDone
{
	return ( total_ == times_ );
}

- (CCActionInterval *) reverse
{
	return [[self class] actionWithAction:[_innerAction reverse] times:times_];
}
@end

//
// Spawn
//
#pragma mark - CCSpawn

@implementation CCSpawn
+(id) actions: (CCFiniteTimeAction*) action1, ...
{
	va_list args;
	va_start(args, action1);

	id ret = [self actions:action1 vaList:args];

	va_end(args);
	return ret;
}

+(id) actions: (CCFiniteTimeAction*) action1 vaList:(va_list)args
{
	CCFiniteTimeAction *now;
	CCFiniteTimeAction *prev = action1;
	
	while( action1 ) {
		now = va_arg(args,CCFiniteTimeAction*);
		if ( now )
			prev = [self actionOne: prev two: now];
		else
			break;
	}

	return prev;
}


+(id) actionWithArray: (NSArray*) actions
{
	CCFiniteTimeAction *prev = [actions objectAtIndex:0];

	for (NSUInteger i = 1; i < [actions count]; i++)
		prev = [self actionOne:prev two:[actions objectAtIndex:i]];

	return prev;
}

+(id) actionOne: (CCFiniteTimeAction*) one two: (CCFiniteTimeAction*) two
{
	return [[[self alloc] initOne:one two:two ] autorelease];
}

-(id) initOne: (CCFiniteTimeAction*) one two: (CCFiniteTimeAction*) two
{
	NSAssert( one!=nil && two!=nil, @"Spawn: arguments must be non-nil");
	NSAssert( one!=one_ && one!=two_, @"Spawn: reinit using same parameters is not supported");
	NSAssert( two!=two_ && two!=one_, @"Spawn: reinit using same parameters is not supported");

	ccTime d1 = [one duration];
	ccTime d2 = [two duration];

	if( (self=[super initWithDuration: MAX(d1,d2)] ) ) {

		// XXX: Supports re-init without leaking. Fails if one==one_ || two==two_
		[one_ release];
		[two_ release];

		one_ = one;
		two_ = two;

		if( d1 > d2 )
			two_ = [CCSequence actionOne:two two:[CCDelayTime actionWithDuration: (d1-d2)] ];
		else if( d1 < d2)
			one_ = [CCSequence actionOne:one two: [CCDelayTime actionWithDuration: (d2-d1)] ];

		[one_ retain];
		[two_ retain];
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initOne: [[one_ copy] autorelease] two: [[two_ copy] autorelease] ];
	return copy;
}

-(void) dealloc
{
	[one_ release];
	[two_ release];
	[super dealloc];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	[one_ startWithTarget:_target];
	[two_ startWithTarget:_target];
}

-(void) stop
{
	[one_ stop];
	[two_ stop];
	[super stop];
}

-(void) update: (ccTime) t
{
	[one_ update:t];
	[two_ update:t];
}

- (CCActionInterval *) reverse
{
	return [[self class] actionOne: [one_ reverse] two: [two_ reverse ] ];
}
@end

//
// RotateTo
//
#pragma mark - CCRotateTo

@implementation CCRotateTo
+(id) actionWithDuration: (ccTime) t angle:(float) a
{
	return [[[self alloc] initWithDuration:t angle:a ] autorelease];
}

-(id) initWithDuration: (ccTime) t angle:(float) a
{
	if( (self=[super initWithDuration: t]) )
		dstAngleX_ = dstAngleY_ = a;

	return self;
}

+(id) actionWithDuration: (ccTime) t angleX:(float) aX angleY:(float) aY
{
	return [[[self alloc] initWithDuration:t angleX:aX angleY:aY ] autorelease];
}

-(id) initWithDuration: (ccTime) t angleX:(float) aX angleY:(float) aY
{
	if( (self=[super initWithDuration: t]) ){
		dstAngleX_ = aX;
    dstAngleY_ = aY;
  }
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] angleX:dstAngleX_ angleY:dstAngleY_];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];

  //Calculate X
	startAngleX_ = [_target rotationX];
	if (startAngleX_ > 0)
		startAngleX_ = fmodf(startAngleX_, 360.0f);
	else
		startAngleX_ = fmodf(startAngleX_, -360.0f);

	diffAngleX_ = dstAngleX_ - startAngleX_;
	if (diffAngleX_ > 180)
		diffAngleX_ -= 360;
	if (diffAngleX_ < -180)
		diffAngleX_ += 360;
  
	
  //Calculate Y: It's duplicated from calculating X since the rotation wrap should be the same
	startAngleY_ = [_target rotationY];
	if (startAngleY_ > 0)
		startAngleY_ = fmodf(startAngleY_, 360.0f);
	else
		startAngleY_ = fmodf(startAngleY_, -360.0f);
  
	diffAngleY_ = dstAngleY_ - startAngleY_;
	if (diffAngleY_ > 180)
		diffAngleY_ -= 360;
	if (diffAngleY_ < -180)
		diffAngleY_ += 360;
}
-(void) update: (ccTime) t
{
	[_target setRotationX: startAngleX_ + diffAngleX_ * t];
	[_target setRotationY: startAngleY_ + diffAngleY_ * t];
}
@end


//
// RotateBy
//
#pragma mark - RotateBy

@implementation CCRotateBy
+(id) actionWithDuration: (ccTime) t angle:(float) a
{
	return [[[self alloc] initWithDuration:t angle:a ] autorelease];
}

-(id) initWithDuration: (ccTime) t angle:(float) a
{
	if( (self=[super initWithDuration: t]) )
		angleX_ = angleY_ = a;

	return self;
}

+(id) actionWithDuration: (ccTime) t angleX:(float) aX angleY:(float) aY
{
	return [[[self alloc] initWithDuration:t angleX:aX angleY:aY ] autorelease];
}

-(id) initWithDuration: (ccTime) t angleX:(float) aX angleY:(float) aY
{
	if( (self=[super initWithDuration: t]) ){
		angleX_ = aX;
    angleY_ = aY;
  }
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] angleX: angleX_ angleY:angleY_];
	return copy;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	startAngleX_ = [_target rotationX];
	startAngleY_ = [_target rotationY];
}

-(void) update: (ccTime) t
{
	// XXX: shall I add % 360
	[_target setRotationX: (startAngleX_ + angleX_ * t )];
	[_target setRotationY: (startAngleY_ + angleY_ * t )];
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration angleX:-angleX_ angleY:-angleY_];
}

@end

//
// MoveBy
//
#pragma mark -
#pragma mark MoveBy

@implementation CCMoveBy
+(id) actionWithDuration: (ccTime) t position: (CGPoint) p
{
	return [[[self alloc] initWithDuration:t position:p ] autorelease];
}

-(id) initWithDuration: (ccTime) t position: (CGPoint) p
{
	if( (self=[super initWithDuration: t]) )
		positionDelta_ = p;
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] position: positionDelta_];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
    previousTick_ = 0;
	[super startWithTarget:aTarget];
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration position:ccp( -positionDelta_.x, -positionDelta_.y)];
}

-(void) update: (ccTime) t
{
    [_target moveBy:ccpMult(positionDelta_, t-previousTick_)];
    //[target_ setPosition: ccpAdd(((CCNode*)target_).position, ccpMult(positionDelta_, t-previousTick_) )];
    previousTick_=t;
}
@end

//
// MoveTo
//
#pragma mark -
#pragma mark MoveTo

@implementation CCMoveTo
+(id) actionWithDuration: (ccTime) t position: (CGPoint) p
{
	return [[[self alloc] initWithDuration:t position:p ] autorelease];
}

-(id) initWithDuration: (ccTime) t position: (CGPoint) p
{
	if( (self=[super initWithDuration: t]) ) {
		endPosition = p;
    }

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] position: endPosition];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	positionDelta_ = ccpSub( endPosition, [(CCNode*)_target position] );
}

@end

//
// SkewTo
//
#pragma mark - CCSkewTo

@implementation CCSkewTo
+(id) actionWithDuration:(ccTime)t skewX:(float)sx skewY:(float)sy
{
	return [[[self alloc] initWithDuration: t skewX:sx skewY:sy] autorelease];
}

-(id) initWithDuration:(ccTime)t skewX:(float)sx skewY:(float)sy
{
	if( (self=[super initWithDuration:t]) ) {
		endSkewX_ = sx;
		endSkewY_ = sy;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] skewX:endSkewX_ skewY:endSkewY_];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];

	startSkewX_ = [_target skewX];

	if (startSkewX_ > 0)
		startSkewX_ = fmodf(startSkewX_, 180.0f);
	else
		startSkewX_ = fmodf(startSkewX_, -180.0f);

	deltaX_ = endSkewX_ - startSkewX_;

	if ( deltaX_ > 180 ) {
		deltaX_ -= 360;
	}
	if ( deltaX_ < -180 ) {
		deltaX_ += 360;
	}

	startSkewY_ = [_target skewY];

	if (startSkewY_ > 0)
		startSkewY_ = fmodf(startSkewY_, 360.0f);
	else
		startSkewY_ = fmodf(startSkewY_, -360.0f);

	deltaY_ = endSkewY_ - startSkewY_;

	if ( deltaY_ > 180 ) {
		deltaY_ -= 360;
	}
	if ( deltaY_ < -180 ) {
		deltaY_ += 360;
	}
}

-(void) update: (ccTime) t
{
	[_target setSkewX: (startSkewX_ + deltaX_ * t ) ];
	[_target setSkewY: (startSkewY_ + deltaY_ * t ) ];
}

@end

//
// CCSkewBy
//
#pragma mark - CCSkewBy

@implementation CCSkewBy

-(id) initWithDuration:(ccTime)t skewX:(float)deltaSkewX skewY:(float)deltaSkewY
{
	if( (self=[super initWithDuration:t skewX:deltaSkewX skewY:deltaSkewY]) ) {
		skewX_ = deltaSkewX;
		skewY_ = deltaSkewY;
	}
	return self;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	deltaX_ = skewX_;
	deltaY_ = skewY_;
	endSkewX_ = startSkewX_ + deltaX_;
	endSkewY_ = startSkewY_ + deltaY_;
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration skewX:-skewX_ skewY:-skewY_];
}
@end


//
// JumpBy
//
#pragma mark - CCJumpBy

@implementation CCJumpBy
+(id) actionWithDuration: (ccTime) t position: (CGPoint) pos height: (ccTime) h jumps:(NSUInteger)j
{
	return [[[self alloc] initWithDuration: t position: pos height: h jumps:j] autorelease];
}

-(id) initWithDuration: (ccTime) t position: (CGPoint) pos height: (ccTime) h jumps:(NSUInteger)j
{
	if( (self=[super initWithDuration:t]) ) {
		delta_ = pos;
		height_ = h;
		jumps_ = j;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] position:delta_ height:height_ jumps:jumps_];
	return copy;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	startPosition_ = [(CCNode*)_target position];
}

-(void) update: (ccTime) t
{
	// Sin jump. Less realistic
//	ccTime y = height * fabsf( sinf(t * (CGFloat)M_PI * jumps ) );
//	y += delta.y * t;
//	ccTime x = delta.x * t;
//	[target setPosition: ccp( startPosition.x + x, startPosition.y + y )];

	// parabolic jump (since v0.8.2)
	ccTime frac = fmodf( t * jumps_, 1.0f );
	ccTime y = height_ * 4 * frac * (1 - frac);
	y += delta_.y * t;
	ccTime x = delta_.x * t;
	[_target setPosition: ccp( startPosition_.x + x, startPosition_.y + y )];

}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration position: ccp(-delta_.x,-delta_.y) height:height_ jumps:jumps_];
}
@end

//
// JumpTo
//
#pragma mark - CCJumpTo

@implementation CCJumpTo
-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	delta_ = ccp( delta_.x - startPosition_.x, delta_.y - startPosition_.y );
}
@end


#pragma mark - CCBezierBy

// Bezier cubic formula:
//	((1 - t) + t)3 = 1
// Expands to…
//   (1 - t)3 + 3t(1-t)2 + 3t2(1 - t) + t3 = 1
static inline CGFloat bezierat( float a, float b, float c, float d, ccTime t )
{
	return (powf(1-t,3) * a +
			3*t*(powf(1-t,2))*b +
			3*powf(t,2)*(1-t)*c +
			powf(t,3)*d );
}

//
// BezierBy
//
@implementation CCBezierBy
+(id) actionWithDuration: (ccTime) t bezier:(ccBezierConfig) c
{
	return [[[self alloc] initWithDuration:t bezier:c ] autorelease];
}

-(id) initWithDuration: (ccTime) t bezier:(ccBezierConfig) c
{
	if( (self=[super initWithDuration: t]) ) {
		config_ = c;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] bezier:config_];
    return copy;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	startPosition_ = [(CCNode*)_target position];
}

-(void) update: (ccTime) t
{
	CGFloat xa = 0;
	CGFloat xb = config_.controlPoint_1.x;
	CGFloat xc = config_.controlPoint_2.x;
	CGFloat xd = config_.endPosition.x;

	CGFloat ya = 0;
	CGFloat yb = config_.controlPoint_1.y;
	CGFloat yc = config_.controlPoint_2.y;
	CGFloat yd = config_.endPosition.y;

	CGFloat x = bezierat(xa, xb, xc, xd, t);
	CGFloat y = bezierat(ya, yb, yc, yd, t);
	[_target setPosition:  ccpAdd( startPosition_, ccp(x,y))];
}

- (CCActionInterval*) reverse
{
	ccBezierConfig r;

	r.endPosition	 = ccpNeg(config_.endPosition);
	r.controlPoint_1 = ccpAdd(config_.controlPoint_2, ccpNeg(config_.endPosition));
	r.controlPoint_2 = ccpAdd(config_.controlPoint_1, ccpNeg(config_.endPosition));

	CCBezierBy *action = [[self class] actionWithDuration:[self duration] bezier:r];
	return action;
}
@end

//
// BezierTo
//
#pragma mark - CCBezierTo
@implementation CCBezierTo
-(id) initWithDuration: (ccTime) t bezier:(ccBezierConfig) c
{
	if( (self=[super initWithDuration: t]) ) {
		toConfig_ = c;
	}
	return self;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	config_.controlPoint_1 = ccpSub(toConfig_.controlPoint_1, startPosition_);
	config_.controlPoint_2 = ccpSub(toConfig_.controlPoint_2, startPosition_);
	config_.endPosition = ccpSub(toConfig_.endPosition, startPosition_);
}
@end


//
// ScaleTo
//
#pragma mark - CCScaleTo
@implementation CCScaleTo
+(id) actionWithDuration: (ccTime) t scale:(float) s
{
	return [[[self alloc] initWithDuration: t scale:s] autorelease];
}

-(id) initWithDuration: (ccTime) t scale:(float) s
{
	if( (self=[super initWithDuration: t]) ) {
		endScaleX_ = s;
		endScaleY_ = s;
	}
	return self;
}

+(id) actionWithDuration: (ccTime) t scaleX:(float)sx scaleY:(float)sy
{
	return [[[self alloc] initWithDuration: t scaleX:sx scaleY:sy] autorelease];
}

-(id) initWithDuration: (ccTime) t scaleX:(float)sx scaleY:(float)sy
{
	if( (self=[super initWithDuration: t]) ) {
		endScaleX_ = sx;
		endScaleY_ = sy;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] scaleX:endScaleX_ scaleY:endScaleY_];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	startScaleX_ = [_target scaleX];
	startScaleY_ = [_target scaleY];
	deltaX_ = endScaleX_ - startScaleX_;
	deltaY_ = endScaleY_ - startScaleY_;
}

-(void) update: (ccTime) t
{
	[_target setScaleX: (startScaleX_ + deltaX_ * t ) ];
	[_target setScaleY: (startScaleY_ + deltaY_ * t ) ];
}
@end

//
// ScaleBy
//
#pragma mark - CCScaleBy
@implementation CCScaleBy
-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	deltaX_ = startScaleX_ * endScaleX_ - startScaleX_;
	deltaY_ = startScaleY_ * endScaleY_ - startScaleY_;
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration scaleX:1/endScaleX_ scaleY:1/endScaleY_];
}
@end

//
// Blink
//
#pragma mark - CCBlink
@implementation CCBlink
+(id) actionWithDuration: (ccTime) t blinks: (NSUInteger) b
{
	return [[[ self alloc] initWithDuration: t blinks: b] autorelease];
}

-(id) initWithDuration: (ccTime) t blinks: (NSUInteger) b
{
	if( (self=[super initWithDuration: t] ) )
		times_ = b;

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] blinks: times_];
	return copy;
}

-(void) startWithTarget:(id)target
{
	[super startWithTarget:target];
	originalState_ = [target visible];
}

-(void) update: (ccTime) t
{
	if( ! [self isDone] ) {
		ccTime slice = 1.0f / times_;
		ccTime m = fmodf(t, slice);
		[_target setVisible: (m > slice/2) ? YES : NO];
	}
}

-(void) stop
{
	[_target setVisible:originalState_];
	[super stop];
}

-(CCActionInterval*) reverse
{
	// return 'self'
	return [[self class] actionWithDuration:_duration blinks: times_];
}
@end

//
// FadeIn
//
#pragma mark - CCFadeIn
@implementation CCFadeIn
-(void) update: (ccTime) t
{
	[(id<CCRGBAProtocol>) _target setOpacity: 255 *t];
}

-(CCActionInterval*) reverse
{
	return [CCFadeOut actionWithDuration:_duration];
}
@end

//
// FadeOut
//
#pragma mark - CCFadeOut
@implementation CCFadeOut
-(void) update: (ccTime) t
{
	[(id<CCRGBAProtocol>) _target setOpacity: 255 *(1-t)];
}

-(CCActionInterval*) reverse
{
	return [CCFadeIn actionWithDuration:_duration];
}
@end

//
// FadeTo
//
#pragma mark - CCFadeTo
@implementation CCFadeTo
+(id) actionWithDuration: (ccTime) t opacity: (GLubyte) o
{
	return [[[ self alloc] initWithDuration: t opacity: o] autorelease];
}

-(id) initWithDuration: (ccTime) t opacity: (GLubyte) o
{
	if( (self=[super initWithDuration: t] ) )
		toOpacity_ = o;

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] opacity:toOpacity_];
	return copy;
}

-(void) startWithTarget:(CCNode *)aTarget
{
	[super startWithTarget:aTarget];
	fromOpacity_ = [(id<CCRGBAProtocol>)_target opacity];
}

-(void) update: (ccTime) t
{
	[(id<CCRGBAProtocol>)_target setOpacity:fromOpacity_ + ( toOpacity_ - fromOpacity_ ) * t];
}
@end

//
// TintTo
//
#pragma mark - CCTintTo
@implementation CCTintTo
+(id) actionWithDuration:(ccTime)t red:(GLubyte)r green:(GLubyte)g blue:(GLubyte)b
{
	return [[(CCTintTo*)[ self alloc] initWithDuration:t red:r green:g blue:b] autorelease];
}

-(id) initWithDuration: (ccTime) t red:(GLubyte)r green:(GLubyte)g blue:(GLubyte)b
{
	if( (self=[super initWithDuration:t] ) )
		to_ = ccc3(r,g,b);

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [(CCTintTo*)[[self class] allocWithZone: zone] initWithDuration:[self duration] red:to_.r green:to_.g blue:to_.b];
	return copy;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];

	id<CCRGBAProtocol> tn = (id<CCRGBAProtocol>) _target;
	from_ = [tn color];
}

-(void) update: (ccTime) t
{
	id<CCRGBAProtocol> tn = (id<CCRGBAProtocol>) _target;
	[tn setColor:ccc3(from_.r + (to_.r - from_.r) * t, from_.g + (to_.g - from_.g) * t, from_.b + (to_.b - from_.b) * t)];
}
@end

//
// TintBy
//
#pragma mark - CCTintBy
@implementation CCTintBy
+(id) actionWithDuration:(ccTime)t red:(GLshort)r green:(GLshort)g blue:(GLshort)b
{
	return [[(CCTintBy*)[ self alloc] initWithDuration:t red:r green:g blue:b] autorelease];
}

-(id) initWithDuration:(ccTime)t red:(GLshort)r green:(GLshort)g blue:(GLshort)b
{
	if( (self=[super initWithDuration: t] ) ) {
		deltaR_ = r;
		deltaG_ = g;
		deltaB_ = b;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	return[(CCTintBy*)[[self class] allocWithZone: zone] initWithDuration: [self duration] red:deltaR_ green:deltaG_ blue:deltaB_];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];

	id<CCRGBAProtocol> tn = (id<CCRGBAProtocol>) _target;
	ccColor3B color = [tn color];
	fromR_ = color.r;
	fromG_ = color.g;
	fromB_ = color.b;
}

-(void) update: (ccTime) t
{
	id<CCRGBAProtocol> tn = (id<CCRGBAProtocol>) _target;
	[tn setColor:ccc3( fromR_ + deltaR_ * t, fromG_ + deltaG_ * t, fromB_ + deltaB_ * t)];
}

- (CCActionInterval*) reverse
{
	return [CCTintBy actionWithDuration:_duration red:-deltaR_ green:-deltaG_ blue:-deltaB_];
}
@end

//
// DelayTime
//
#pragma mark - CCDelayTime
@implementation CCDelayTime
-(void) update: (ccTime) t
{
	return;
}

-(id)reverse
{
	return [[self class] actionWithDuration:_duration];
}
@end

//
// ReverseTime
//
#pragma mark - CCReverseTime
@implementation CCReverseTime
+(id) actionWithAction: (CCFiniteTimeAction*) action
{
	// casting to prevent warnings
	CCReverseTime *a = [self alloc];
	return [[a initWithAction:action] autorelease];
}

-(id) initWithAction: (CCFiniteTimeAction*) action
{
	NSAssert(action != nil, @"CCReverseTime: action should not be nil");
	NSAssert(action != other_, @"CCReverseTime: re-init doesn't support using the same arguments");

	if( (self=[super initWithDuration: [action duration]]) ) {
		// Don't leak if action is reused
		[other_ release];
		other_ = [action retain];
	}

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	return [[[self class] allocWithZone: zone] initWithAction:[[other_ copy] autorelease] ];
}

-(void) dealloc
{
	[other_ release];
	[super dealloc];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	[other_ startWithTarget:_target];
}

-(void) stop
{
	[other_ stop];
	[super stop];
}

-(void) update:(ccTime)t
{
	[other_ update:1-t];
}

-(CCActionInterval*) reverse
{
	return [[other_ copy] autorelease];
}
@end

//
// Animate
//

#pragma mark - CCAnimate
@implementation CCAnimate

@synthesize animation = animation_;

+(id) actionWithAnimation: (CCAnimation*)anim
{
	return [[[self alloc] initWithAnimation:anim] autorelease];
}

// delegate initializer
-(id) initWithAnimation:(CCAnimation*)anim
{
	NSAssert( anim!=nil, @"Animate: argument Animation must be non-nil");
	
	float singleDuration = anim.duration;

	if( (self=[super initWithDuration:singleDuration * anim.loops] ) ) {

		nextFrame_ = 0;
		self.animation = anim;
		origFrame_ = nil;
		executedLoops_ = 0;
		
		splitTimes_ = [[NSMutableArray alloc] initWithCapacity:anim.frames.count];
		
		float accumUnitsOfTime = 0;
		float newUnitOfTimeValue = singleDuration / anim.totalDelayUnits;
		
		for( CCAnimationFrame *frame in anim.frames ) {

			NSNumber *value = [NSNumber numberWithFloat: (accumUnitsOfTime * newUnitOfTimeValue) / singleDuration];
			accumUnitsOfTime += frame.delayUnits;

			[splitTimes_ addObject:value];
		}		
	}
	return self;
}


-(id) copyWithZone: (NSZone*) zone
{
	return [[[self class] allocWithZone: zone] initWithAnimation:[[animation_ copy]autorelease] ];
}

-(void) dealloc
{
	[splitTimes_ release];
	[animation_ release];
	[origFrame_ release];
	[super dealloc];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	CCSprite *sprite = _target;

	[origFrame_ release];

	if( animation_.restoreOriginalFrame )
		origFrame_ = [[sprite displayFrame] retain];
	
	nextFrame_ = 0;
	executedLoops_ = 0;
}

-(void) stop
{
	if( animation_.restoreOriginalFrame ) {
		CCSprite *sprite = _target;
		[sprite setDisplayFrame:origFrame_];
	}

	[super stop];
}

-(void) update: (ccTime) t
{
	
	// if t==1, ignore. Animation should finish with t==1
	if( t < 1.0f ) {
		t *= animation_.loops;
		
		// new loop?  If so, reset frame counter
		NSUInteger loopNumber = (NSUInteger)t;
		if( loopNumber > executedLoops_ ) {
			nextFrame_ = 0;
			executedLoops_++;
		}
		
		// new t for animations
		t = fmodf(t, 1.0f);
	}
	
	NSArray *frames = [animation_ frames];
	NSUInteger numberOfFrames = [frames count];
	CCSpriteFrame *frameToDisplay = nil;

	for( NSUInteger i=nextFrame_; i < numberOfFrames; i++ ) {
		NSNumber *splitTime = [splitTimes_ objectAtIndex:i];

		if( [splitTime floatValue] <= t ) {
			CCAnimationFrame *frame = [frames objectAtIndex:i];
			frameToDisplay = [frame spriteFrame];
			[(CCSprite*)_target setDisplayFrame: frameToDisplay];
			
			NSDictionary *dict = [frame userInfo];
			if( dict )
				[[NSNotificationCenter defaultCenter] postNotificationName:CCAnimationFrameDisplayedNotification object:_target userInfo:dict];

			nextFrame_ = i+1;
		}
		// Issue 1438. Could be more than one frame per tick, due to low frame rate or frame delta < 1/FPS
		else
			break;
	}
}

- (CCActionInterval *) reverse
{
	NSArray *oldArray = [animation_ frames];
	NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:[oldArray count]];
    NSEnumerator *enumerator = [oldArray reverseObjectEnumerator];
    for (id element in enumerator)
        [newArray addObject:[[element copy] autorelease]];

	CCAnimation *newAnim = [CCAnimation animationWithAnimationFrames:newArray delayPerUnit:animation_.delayPerUnit loops:animation_.loops];
	newAnim.restoreOriginalFrame = animation_.restoreOriginalFrame;
	return [[self class] actionWithAnimation:newAnim];
}
@end


#pragma mark - CCTargetedAction

@implementation CCTargetedAction

@synthesize forcedTarget = forcedTarget_;

+ (id) actionWithTarget:(id) target action:(CCFiniteTimeAction*) action
{
	return [[ (CCTargetedAction*)[self alloc] initWithTarget:target action:action] autorelease];
}

- (id) initWithTarget:(id) targetIn action:(CCFiniteTimeAction*) actionIn
{
	if((self = [super initWithDuration:actionIn.duration]))
	{
		forcedTarget_ = [targetIn retain];
		action_ = [actionIn retain];
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [ (CCTargetedAction*) [[self class] allocWithZone: zone] initWithTarget:forcedTarget_ action:[[action_ copy] autorelease]];
	return copy;
}

- (void) dealloc
{
	[forcedTarget_ release];
	[action_ release];
	[super dealloc];
}

//- (void) updateDuration:(id)aTarget
//{
//	[action updateDuration:forcedTarget];
//	_duration = action.duration;
//}

- (void) startWithTarget:(id)aTarget
{
	[super startWithTarget:_target];
	[action_ startWithTarget:forcedTarget_];
}

- (void) stop
{
	[action_ stop];
}

- (void) update:(ccTime) time
{
	[action_ update:time];
}

@end
