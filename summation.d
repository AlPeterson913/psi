// Written in the D programming language
// License: http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0

import dexpr, util;

DExpr computeSum(DExpr expr,DExpr facts=one){
	auto var=dDeBruijnVar(1);
	auto nexpr=expr.simplify(facts.incDeBruijnVar(1,0).simplify(one));
	if(nexpr !is expr) expr=nexpr;
	if(expr is zero) return zero;
	auto ow=expr.splitMultAtVar(var); // not a good strategy without modification, due to deltas
	ow[0]=ow[0].incDeBruijnVar(-1,0).simplify(facts);
	if(ow[0] !is one){
		if(auto r=computeSum(ow[1],facts))
			return (ow[0]*r).simplify(facts);
		return null;
	}
	if(expr is one) return null; // (infinite sum)
	foreach(f;expr.factors){
		if(auto p=cast(DPlus)f){
			bool check(){ // TODO: deltas?
				foreach(d;p.allOf!DIvr(true))
					if(d.hasFreeVar(var))
						return true;
				return false;
			}
			if(check()){
				DExprSet works;
				DExprSet doesNotWork;
				bool simpler=false;
				foreach(k;distributeMult(p,expr.withoutFactor(f))){
					k=k.simplify(facts.incDeBruijnVar(1,0).simplify(one));
					auto ow=k.splitMultAtVar(var);
					auto r=computeSum(ow[1],facts);
					if(r){
						ow[0]=ow[0].incDeBruijnVar(-1,0);
						DPlus.insert(works,ow[0]*r);
						simpler=true;
					}else DPlus.insert(doesNotWork,k);
				}
				if(simpler){
					auto r=dPlus(works).simplify(facts);
					if(doesNotWork.length) r = r + dSum(dPlus(doesNotWork));
					return r;
				}
			}
		}
	}
	nexpr=expr.linearizeConstraints!(x=>!!cast(DIvr)x)(var).simplify(facts.incDeBruijnVar(1,0).simplify(one));
	if(nexpr !is expr) return computeSum(nexpr,facts);

	// TODO: keep ivrs and nonIvrs separate in DMult
	DExpr ivrs=one;
	DExpr nonIvrs=one;
	foreach(f;expr.factors){
		assert(f.hasFreeVar(var));
		auto ivr=cast(DIvr)f;
		if(ivr&&ivr.type!=DIvr.Type.neqZ) ivrs=ivrs*f;
		else nonIvrs=nonIvrs*f;
	}
	ivrs=ivrs.simplify(facts.incDeBruijnVar(1,0).simplify(one));
	nonIvrs=nonIvrs.simplify(facts.incDeBruijnVar(1,0).simplify(one));
	DExpr lower,upper;
	foreach(f;ivrs.factors){
		if(f is one) break;
		auto ivr=cast(DIvr)f;
		assert(!!ivr);
		assert(ivr.type!=DIvr.Type.neqZ);
		DExpr bound;
		auto status=ivr.getBoundForVar(var,bound);
		if(bound) bound=bound.incDeBruijnVar(-1,0);
		final switch(status) with(BoundStatus){
		case fail:
			return null;
		case lowerBound:
			if(lower) lower=dMax(lower,bound);
			else lower=bound;
			lower=lower.simplify(facts);
			break;
		case upperBound:
			if(upper) upper=dMin(upper,bound);
			else upper=bound;
			upper=upper.simplify(facts);
			break;
		case equal:
			if(lower) lower=dMax(lower,bound);
			else lower=bound;
			if(upper) upper=dMin(upper,bound);
			else upper=bound;
			lower=lower.simplify(facts);
			upper=upper.simplify(facts);
		}
	}
	//dw("!! ",nonIvrs," ",lower," ",upper);
	// TODO: use more clever summation strategies first
	if(lower && upper && lower.isFraction() && upper.isFraction()){
		auto ndl=lower.getFraction();
		auto ndu=upper.getFraction();
		auto low=ceildiv(ndl[0],ndl[1]);
		auto up=floordiv(ndu[0],ndu[1]);
		DExprSet s;
		if(low<=up) foreach(i;low..up+1){ // TODO: report bug in std.bigint (the if condition should not be necessary)
			DPlus.insert(s,unbind(nonIvrs,dℤ(i)).simplify(facts));
		}
		return dPlus(s);
	}
	return null;
}
