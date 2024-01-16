# Macro Allocation

Implements optimal sample allocation for stratified simple random sampling using the method described by Tommy Wright "A Simple Method of Exact Optimal Sample Allocation 
under Stratification with Any Mixed Constraint Patterns"
https://www.census.gov/library/working-papers/2014/adrm/rrs2014-07.html

Also implement an extension to Bernoulli sampling.

## Syntax:

```SAS
%macro Allocation(
		Selection=SRS,
		SampleSize=,
		MinSize=,
		Subdiv=1,
		LogPrint= yes,
	
		StratCons=,

		StratInfo=,
		VarInfo=,

		AllocOut= _allocOut,
		InfoOut = 
);
```

## Parameters: 

### Input:

Selection (SRS Bern)  
SampleSize (numeric>0)  
MinSize (numeric >0)  
Subdiv (integer >= 1)  
LogPrint (yes no)  

StratCons : StratID LB UB   

StratInfo : StratID Count   
VarInfo : StratID VarID Total Variance Aux  


### Output:

AllocOut : StratId Size  
AllocOutInfo : StratId Count LB UB Size Obj Variance  
_ALLOCATIONSTATUS (OK ERROR)  
_ALLOCATIONObjective (numeric >0)   


```
