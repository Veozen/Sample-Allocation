/*Allocation*/

%macro Nobs(dataIn);
/*Returns the number of observations in a dataset*/
	%local dataid nobs rc;
	%let nobs=0;
	%if (&dataIn ne ) %then %do;
		%let dataid=%sysfunc(open(&dataIn));
		%let nobs=%sysfunc(attrn(&dataid,nobs));
		%let rc=%sysfunc(close(&dataid));
	%end;
	&nobs 
%mend Nobs;

%macro saveOptions();
	/*save some common options*/
	%local notes mprint symbolgen source options;
	%let notes = %sysfunc(getoption(Notes));
	%let mprint = %sysfunc(getoption(mprint));
	%let symbolgen = %sysfunc(getoption(Symbolgen));
	%let source = %sysfunc(getoption(source));

	%let options = &notes &mprint &symbolgen &source;
	&options;
%mend saveOptions;

%macro Time(from);
/*returns the current time  or if input provided: 
returns the elaspsed time from the input time */
	%local dataTime now time;
	%let datetime = %sysfunc( datetime() );
	%let now=%sysfunc( timepart(&datetime) );

	%if (&from ne ) %then %do;
		%let timefrom = %sysfunc(inputn(&from,time9.));
		%if %sysevalf(&now<&timefrom) %then %do;
			%let time =  %sysevalf(86400-&timefrom,ceil);
			%let time = %sysevalf(&time + %sysevalf(&now,ceil));
		%end;
		%else %do;
			%let time = %sysevalf(&now-&timefrom,ceil);
		%end;
		%let time = %sysfunc(putn(&time,time9.));
	%end;
	%else %do;
		%let time = &now;
		%let time = %sysfunc(putn(&time,time9.));
	%end;
	&time
%mend Time;

%macro Sum(data,Var);
/* yields the sum of a dataset s variable*/
	%local i dataid varnum nobs sum rc var;
	%let dataid=%sysfunc(open(&data));
	%let varnum=%sysfunc(varnum(&dataId,&var));
	%let nobs = %sysfunc(attrn(&dataId,nobs));
	%let sum=0;
	%do i = 1 %to &nobs;
		%let rc= %sysfunc(fetch(&dataId));
		%let var = %sysfunc(getvarN(&dataId,&varnum));
		%let sum= %sysevalf(&sum+&var);
	%end;
	%let rc = %sysfunc(close(&dataId));
	&sum
%mend Sum;

%macro varType(data,var);
	/*return a list of types for the variables of a Data set*/
	%local id nvar types rc N i varnum n;
	%let id= %sysfunc(open(&data));

	%if (&var eq) %then %do;
		%let nvar=%sysfunc(attrn(&id,nvar));
		%let types=;
		%do i = 1 %to &nvar;
			%let types= &types %sysfunc(varType(&id,&i));
		%end;
	%end;
	%else %do;
		%let n=  %sysfunc(countw(&var,%str( )));
		%let types=;
		%do i = 1 %to &n;
			%let varnum = %sysfunc(varnum(&id,%scan(&var,&i)));
			%let types= &types %sysfunc(varType(&id,&varnum));
		%end;
	%end;

	%let rc= %sysfunc(close(&id));
	&types
%mend varType;

%macro varExist_(Data,var);
	/*Check if a set of variables exists in a data set */
	%local count DSID varexist N varnum;
	%let DSID = %sysfunc(open(&Data));
	%let n=  %sysfunc(countw(&var,%str( )));

	%let count = 1;
	%let varexist=1;
	%do %while(&count <= &N);
		%let varnum = %sysfunc(varnum(&DSID, %scan(&var,&count)));
		%if &varnum eq 0 %then %do;
			%let varexist=0;
		%end;
		%let count = %eval(&count + 1);
	%end;
	
	%let DSID = %sysfunc(close(&DSID));
	&varexist 
%mend varExist_;
%macro Alloc_NeyOptimal();
	/*Census Bureau Optimal Allocation*/
	%local lowerSize Ndup;
	%let lowerSize= %Sum(&InfoOut,lb);
/*
	data _factor;
		set &InfoOut;
		_factors = (Count**2)*obj;

		
		do i = 1 to (&SampleSize-&lowerSize-1);
			if (i ge lb) and (i lt ub) then do;
				_Priorityfactors=_factors/(i*(i+1));
				output;
			end;;
		end;
		
	run;*/
	
	data _factor;
		set &InfoOut;
		_factors = (Count**2)*obj;

		Lim = min((ub-1),(&SampleSize-&lowerSize-1));
		
		do i = lb to Lim;
				_Priorityfactors=  _factors /(i*(i+1)) ;
				output;
		end;
		
		drop lim;
	run;

	proc sort data= _factor; by descending _Priorityfactors; run;

	data _factors _factors_low;
		set _factor;

		if _N_ le (&SampleSize-&lowerSize) then output _factors;
		else output _factors_low;
	run;

	/*
	proc sql noprint;
		select count(*) into : NDup
		from _factors as a , _factors_low as b
		where a._Priorityfactors=b._Priorityfactors
		;
	quit;

	%if &NDup gt 0 %then %do;	
		%put     WARNING: Optimal Allocation has multiple solutions;
	%end;
	*/

	proc sort data= _factors; by StratId ; run;
	proc means data= _factors noprint; by StratId; output out=_sizeOut (keep = StratId size) n=size;run;


	proc sql noprint;
		create table &InfoOut._ as
		select a.*, b.Size
		from &InfoOut as a left join _sizeOut as b
		on a.StratId=b.StratId
		;
	quit;

	data &InfoOut;
		set &InfoOut._ ;
		
		if missing(size) then size=0;
		size=size+lb;

	run;

	proc delete data= _sizeOut _factor _factors _factors_low; run;

%mend Alloc_NeyOptimal;

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
/*
Input 

	Selection (SRS Bern)
	SampleSize (numeric>0)
	MinSize (numeric >0)
	Subdiv (integer >= 1)
	LogPrint (yes no)

	StratCons : StratID LB UB 

	StratInfo : StratID Count 
	VarInfo : StratID VarID Total Variance Aux


Output

	AllocOut : StratId Size
	AllocOutInfo : StratId Count LB UB Size Obj Variance
	_ALLOCATIONSTATUS (OK ERROR)
	_ALLOCATIONObjective (numeric >0) 
*/

	%global  _ALLOCATIONSTATUS _ALLOCATIONObjective;
	%local Nstrat StratconsError options startTime objective InfoOutdelete SampSize;
	%let options = %saveOptions();
	%let _ALLOCATIONSTATUS = OK;
	%let _ALLOCATIONObjective= ;
	
	options nonotes nomprint nosource nosymbolgen;

	%let StartTime= %Time();

	%if (%upcase(&logPrint) eq YES) %then %do;
		%put ;
		%put ----------;
		%put Allocation;
		%put ----------;
		%put;
	%end;

	/*Verifications des paramètres*/
	%if (%upcase(&selection) ne BERN) and (%upcase(&selection) ne SRS) %then %do;
		%put ERROR: Selection method must be either SRS or BERN; 
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&InfoOut eq ) %then %do;
		%let InfoOutDelete =1;
		%let InfoOut = _allocOutInfo;
	%end;
	%if (&InfoOut eq &allocOut) %then %do;
		%let InfoOutDelete =1;
		%let InfoOut = &allocOut._;
	%end;

	%if (&subdiv eq ) or (&subDiv lt 1) %then %do;
		%put WARNING: SubDiv must be at least 1;
		%let subDiv=1;
	%end;
	%if (&minSize ne ) and ( &minSize lt %sysevalf(1/&subdiv) ) %then %do;
		%put WARNING: MinSize must be at least %sysevalf(1/&subdiv);
		%let minsize = %sysevalf(1/&subdiv);
	%end;

	%if (&sampleSize eq ) %then %do;
		%put ERROR:  SampleSize must be be provided; 
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (&sampleSize ne ) and %sysevalf(&sampleSize lt 1) %then %do;
		%put ERROR:  SampleSize must be greater than 0; 
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&stratInfo eq ) %then %do;
		%put ERROR: StratInfo must be provided;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (&varInfo eq ) %then %do;
		%put ERROR: VarInfo must be provided;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;



	/*Vérification des fichiers d entré*/
	%if (not %sysfunc(exist(&stratInfo))) %then %do;
		%put ERROR: StratInfo does not exist;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (not %sysfunc(exist(&varInfo))) %then %do;
		%put ERROR: VarInfo does not exist;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&stratCons ne ) and (not %sysfunc(exist(&stratCons))) %then %do;
		%put ERROR: StratCons does not exist;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (%varType(&stratInfo,stratId) ne %varType(&varInfo,stratId)) %then %do;
		%put ERROR: stratId types do not match in files stratInfo and VarInfo;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&stratCons ne )  %then %do;
			%if (%varType(&stratCons,stratId) ne %varType(&varInfo,stratId)) %then %do;
				%put ERROR: stratId types do not match in files stratCons and VarInfo;
				%let _ALLOCATIONSTATUS = ERROR;
				%goto exit;
			%end;
	%end;


	%if (%varExist_(&stratInfo,STRATID COUNT) eq 0)  %then %do;
		%put ERROR: StratInfo must contain variables StratId and Count;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (%upcase(&selection) eq SRS) %then %do;
		%if (%varExist_(&varInfo,STRATID VARID VARIANCE aux) eq 0)  %then %do;
			%put ERROR: VarInfo must contain variables StratId, VarId, Variance and Aux;
			%let _ALLOCATIONSTATUS = ERROR;
			%goto exit;
		%end;
	%end;
	%if (%upcase(&selection) eq BERN) %then %do;
		%if (%varExist_(&varInfo,STRATID VARID total VARIANCE aux) eq 0)  %then %do;
			%put ERROR: VarInfo must contain variables StratId, VarId, Total, Variance and Aux;
			%let _ALLOCATIONSTATUS = ERROR;
			%goto exit;
		%end;
	%end;




	/*Vérification du contenu de StratInfo VarInfo et StratCons*/
	data _StratInfo;
		set &stratInfo ;
		if not missing(Count);

		keep stratId Count ;
	run;
	proc sort data=_StratInfo nodupkey; by StratId; run;
	proc sql;
		create table _stratList as
		select distinct stratId 
		from &stratInfo 
		order by stratId;
	quit;
	%let NStrat	= %Nobs(_stratList);
	%if %Nobs(&StratInfo) gt &Nstrat %then %do;
		proc delete data = _stratList _StratInfo; run;
		%put ERROR: StratInfo contains missing Count or duplicate StratId;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	proc sql;
		create table _VarInfo as
		select s.*
		from _stratList as v left join &varInfo as s 
		on v.stratId=s.stratId;
	quit;
	data _varInfo;
		set _varInfo;
		if not missing(StratId);

		if missing(aux) then aux=1;
		if missing(variance) then variance=0;
		if missing(total) then total =0;
		keep StratId VarId total variance aux ;
	run;
	proc sort data=_varInfo nodupkey; by StratId VarId; run;
	%if %Nobs(_VarInfo) lt &Nstrat %then %do;
		proc delete data = _varInfo; run;
		%put ERROR: VarInfo doesnt cover all StratId in StratInfo or VarInfo contains duplicate pairs StratId VarId ;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&stratCons ne ) %then %do;
		proc sql;
			create table _stratCons as
			select s.*
			from &stratCons(keep = StratId lb ub) as s, _stratList as v
			where s.stratId=v.stratId
			order by s.stratId;
		quit;
		data _stratCons;
			merge _stratCons _stratInfo ;
			by stratId;

			%if (&minSize ne ) %then %do;
				if missing(lb) then lb=&minSize;
				if lb lt 0 then lb=&minSize;
			%end;
			if missing(lb) then lb=1/&subdiv;
			if lb lt 1 then lb=1/&subdiv;
			
			if missing(ub) then ub=count;
			if ub gt count then ub = count;
		run;
	%end;
	%else %do;
		data _stratCons;
			set _stratInfo(keep=stratId Count);
			lb=1/&subdiv;
			%if (&minSize ne ) %then %do;
				lb=&minSize;
			%end;
			ub=count;
		run;
	%end;
	%let StratconsError=0;
	data _stratCons;
		set _stratCons;

		if lb gt ub then do;
			call symputx("StratConsError",1);
		end;
	run;
	%if (&StratConsError = 1) %then %do;
		proc delete data = _stratList _stratInfo _VarInfo _stratCons;run;
		%put  ERROR: lower bound greater than upper bound ;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	

	/*Vérification des contraintes de taille*/
	%if %sysevalf(%Sum(_stratCons,lb) gt &sampleSize) %then %do;
		%put %Sum(_stratCons,lb) &sampleSize;
		%put ERROR: Sample size is too small to satisfy constraints;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if %sysevalf(%Sum(_stratCons,ub) lt &sampleSize) %then %do;
		%put %Sum(_stratCons,ub) &sampleSize;
		%put ERROR: Sample size is too large to be satisfied with the provided constraints;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;



	/*Préparation */
	proc sql noprint;
		create table &InfoOut as
		select a.*, b.Count
		from _varInfo as a left join _stratInfo as b
		on a.StratId=b.StratId;
	quit;
	data &InfoOut;
		set &InfoOut;
		%if (%upcase(&Selection) eq SRS) %then %do;
			_varExp= aux*variance;
		%end;
		%if (%upcase(&Selection) eq BERN) %then %do;
			*_varExp= aux* ((variance*(Count-1)/Count) + ((Total/Count)**2));
			_varExp= aux*variance;
		%end;
	run;
	proc sort data=&InfoOut; by stratId ;run;
	proc means data=&InfoOut noprint; by stratId;var _varExp; output out=_LinVar(drop=_type_ _freq_) sum=obj;run;
	proc sql noprint;
		create table &InfoOut._ as
		select a.*, b.obj
		from _stratInfo as a left join _LinVar as b
		on a.StratId=b.StratId;
	quit;
	proc sql noprint;
		create table &InfoOut as
		select a.* , b.lb, b.ub
		from  &InfoOut._ as a left join _StratCons as b
		on a.StratId=b.StratId
		;
	quit;
	data &infoOut;
		set &infoOut;

		lb=lb*&subDiv;
		ub=Ub*&SubDiv;
	run;
	%let SampSize=&SampleSize;
	%let SampleSize=%sysevalf(&sampleSize * &subdiv);


	/*Calcul de la répartition*/
	%Alloc_NeyOptimal();

	%let SampleSize= &SampSize;

	/*Output*/
	data &InfoOut;
		set &InfoOut;
		
		size=size/&subdiv;
		lb=lb/&subDiv;
		ub=ub/&subDiv;

		variance= (count**2)*(1/size - 1/count)*obj;
	run;
	data &InfoOut;
		retain StratId Count LB UB Size Obj Variance;
		set &infoOut;

		keep StratId Count LB UB Size Obj Variance;
	run;
	data &allocOut;
		set &InfoOut;
		%if %upcase(&Selection) eq BERN %then %do;
			size=size/Count;
		%end;
		keep StratId size;
	run;
	

	/*Affichage et sortie*/
	%if (%upcase(&logPrint) eq YES) %then %do;
		%put %str(   ) Selection Method  : %upcase(&selection);
		%put;
		%put %str(   ) Number of Strata : %Nobs(_stratList);
		%put %str(   ) SampleSize       : %Sum(&InfoOut,size);
		%put;
		%put %str(   ) Objective Function : %Sum(&InfoOut,variance);
	%end;
	

	%let _ALLOCATIONObjective =  %Sum(&InfoOut,variance);

	%if (&InfoOutDelete eq 1) %then %do;
		proc delete data = &InfoOut ;run;
	%end;

	proc delete data = _stratList _stratInfo _VarInfo _stratCons &InfoOut._  _LinVar ;run;

	%exit:
	%if (%upcase(&logPrint) eq YES) %then %do;
		%put;
		%put Start 	at &StartTime;
		%put End    at %Time();
	%end;

	options &options;

%mend Allocation;

%macro ObjFunc(
					Selection=SRS,

					StratInfo=,
					VarInfo=,
					infoOut=_infoOut
);
/*
Input 

	Selection (SRS Bern)

	StratInfo : StratID Count Size
	VarInfo : StratID VarID total Variance Aux

Output

	_ALLOCATIONSTATUS (OK ERROR)
	_ALLOCATIONObjective (numeric >0) 
*/

	%global  _ALLOCATIONSTATUS _ALLOCATIONObjective;
	%local Nstrat options startTime InfoOut;
	%let options = %saveOptions();
	%let _ALLOCATIONSTATUS = OK;
	%let _ALLOCATIONObjective= ;
	/*%let InfoOut=_infoOut;*/
	
	options nonotes nomprint nosource nosymbolgen;

	%let StartTime= %Time();

	%put ;
	%put ----------;
	%put Allocation;
	%put ----------;
	%put;

	/*Verifications des paramètres*/
	%if (%upcase(&selection) ne BERN) and (%upcase(&selection) ne SRS) %then %do;
		%put ERROR: Selection method must be either SRS or BERN; 
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (&stratInfo eq ) %then %do;
		%put ERROR: StratInfo must be provided;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (&varInfo eq ) %then %do;
		%put ERROR: VarInfo must be provided;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;


	/*Vérification des fichiers d entré*/
	%if (not %sysfunc(exist(&stratInfo))) %then %do;
		%put ERROR: StratInfo does not exist;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (not %sysfunc(exist(&varInfo))) %then %do;
		%put ERROR: VarInfo does not exist;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	%if (%varType(&stratInfo,stratId) ne %varType(&varInfo,stratId)) %then %do;
		%put ERROR: stratId types do not match in files stratInfo and VarInfo;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;


	%if (%varExist_(&stratInfo,STRATID COUNT size) eq 0)  %then %do;
		%put ERROR: StratInfo must contain variables StratId, Count and Size;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	%if (%upcase(&selection) eq SRS) %then %do;
		%if (%varExist_(&varInfo,STRATID VARID VARIANCE aux) eq 0)  %then %do;
			%put ERROR: VarInfo must contain variables StratId, VarId, Variance and Aux;
			%let _ALLOCATIONSTATUS = ERROR;
			%goto exit;
		%end;
	%end;
	%if (%upcase(&selection) eq BERN) %then %do;
		%if (%varExist_(&varInfo,STRATID VARID total VARIANCE aux) eq 0)  %then %do;
			%put ERROR: VarInfo must contain variables StratId, VarId, Total, Variance and Aux;
			%let _ALLOCATIONSTATUS = ERROR;
			%goto exit;
		%end;
	%end;




	/*Vérification du contenu de StratInfo VarInfo et StratCons*/
	data _StratInfo;
		set &stratInfo ;
		if not missing(Count);

		keep stratId Count Size;
	run;
	proc sort data=_StratInfo nodupkey; by StratId; run;
	proc sql;
		create table _stratList as
		select distinct stratId 
		from &stratInfo 
		order by stratId;
	quit;
	%let NStrat	= %Nobs(_stratList);
	%if %Nobs(&StratInfo) gt &Nstrat %then %do;
		proc delete data = _stratList _StratInfo; run;
		%put ERROR: StratInfo contains missing Count or duplicate StratId;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;

	proc sql;
		create table _VarInfo as
		select s.*
		from _stratList as v left join &varInfo as s 
		on v.stratId=s.stratId;
	quit;
	data _varInfo;
		set _varInfo;
		if not missing(StratId);

		if missing(aux) then aux=1;
		if missing(variance) then variance=0;
		if missing(total) then total =0;
		keep StratId VarId total variance aux ;
	run;
	proc sort data=_varInfo nodupkey; by StratId VarId; run;
	%if %Nobs(_VarInfo) lt &Nstrat %then %do;
		proc delete data = _varInfo; run;
		%put ERROR: VarInfo doesnt cover all StratId in StratInfo or VarInfo contains duplicate pairs StratId VarId ;
		%let _ALLOCATIONSTATUS = ERROR;
		%goto exit;
	%end;
	


	/*Préparation */
	proc sql noprint;
		create table &InfoOut as
		select a.*, b.Count
		from _varInfo as a left join _stratInfo as b
		on a.StratId=b.StratId;
	quit;
	data &InfoOut;
		set &InfoOut;
		%if (%upcase(&Selection) eq SRS) %then %do;
			_varExp= aux*variance;
		%end;
		%if (%upcase(&Selection) eq BERN) %then %do;
			_varExp= aux* ((variance*(Count-1)/Count) + ((Total/Count)**2));
		%end;
	run;
	proc sort data=&InfoOut; by stratId ;run;
	proc means data=&InfoOut noprint; by stratId;var _varExp; output out=_LinVar(drop=_type_ _freq_) sum=obj;run;
	proc sql noprint;
		create table &InfoOut as
		select a.*, b.obj
		from _stratInfo as a left join _LinVar as b
		on a.StratId=b.StratId;
	quit;





	/*Output*/
	data &InfoOut;
		set &InfoOut;

		if size gt count then size = count;

		variance= (count**2)*(1/size - 1/count)*obj;
		if size eq count then variance =0;
	run;
	data &InfoOut;
		retain StratId Count Size Obj Variance;
		set &infoOut;

		keep StratId Count Size Obj Variance;
	run;

	

	%put %str(   ) Selection Method  : %upcase(&selection);
	%put;
	%put %str(   ) Number of Strata : %Nobs(_stratList);
	%put %str(   ) SampleSize       : %Sum(&InfoOut,size);
	%put;
	%put %str(   ) Objective Function : %Sum(&InfoOut,variance);
	

	%let _ALLOCATIONObjective =  %Sum(&InfoOut,variance);


	proc delete data = _stratList _stratInfo _VarInfo  _LinVar  ;run; /*&InfoOut*/

	%exit:
	%put;
	%put Start 	at &StartTime;
	%put End    at %Time();

	options &options;

%mend ObjFunc;


