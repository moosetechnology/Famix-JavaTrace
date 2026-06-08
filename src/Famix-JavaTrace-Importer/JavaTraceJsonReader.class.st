"
## Usage 
```
file := '/Path/To/.../JDIOutput.tr' asFileReference.
model := CallStackJsonReader import: file.
```
	
	

"
Class {
	#name : 'JavaTraceJsonReader',
	#superclass : 'Object',
	#instVars : [
		'filename',
		'model',
		'createdPrimitives',
		'createdMethods',
		'createdReference',
		'createdSourcesPackages',
		'defaultPackage',
		'createdTypes',
		'createdElements'
	],
	#category : 'Famix-JavaTrace-Importer',
	#package : 'Famix-JavaTrace-Importer'
}

{ #category : 'api' }
JavaTraceJsonReader class >> import: aFileReference [

	^ self new readFrom: aFileReference
]

{ #category : 'class initialization' }
JavaTraceJsonReader class >> initialize [

	self registerExternalDropHandler
]

{ #category : 'class initialization' }
JavaTraceJsonReader class >> registerExternalDropHandler [
	ExternalDropHandler registerHandler: (ExternalDropHandler type: nil extension: #tr action: [ :fileReference |
				 (self import: fileReference)
					 install;
					 inspect ])
]

{ #category : 'as yet unclassified' }
JavaTraceJsonReader >> chooseMethodTypeFrom: aDictionnary [

	aDictionnary at: #isParametric ifPresent: [ :bool | bool ifTrue: [ ^ FamixJavaParametricMethod ] ].
	^ FamixJavaMethod
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createArgument: aCollection [
	"Instiantiate an argument given to a method in a TraceMethod"
	| arg |
	arg := model newArgument.
	aCollection ifNotNil: [ arg value: (self createValueWith: aCollection) ].
	^ arg
]

{ #category : 'as yet unclassified' }
JavaTraceJsonReader >> createArguments: aDictionary forTraceMethod: aTraceMethod [

	| accessible argValuesDict |
	"Default: accessible if not specified"
	accessible := aDictionary at: #accessible ifAbsent: true.
	"Default: accessible if not specified"
	argValuesDict := aDictionary at: #argsValues ifAbsent: nil.
	aTraceMethod isArgsAccessible: accessible.

	"Checking if the method call has a valid construction
	Should be either
	- accessible and have a value
	- inaccessible and dont have a value"
	accessible ~= argValuesDict notNil ifTrue: [ Error signal: 'Invalid methodCall arguments accessibility or description' ].

	accessible ifTrue: [ argValuesDict do: [ :argDict | aTraceMethod addArgument: (self createArgument: argDict) ] ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createArrayValueWith: aCollection [
	"Instantiate an ArrayValue"

	^ model newArrayValue value: (aCollection ifNotNil: [ self createValueWith: aCollection ])
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createField: aDictionary [
	"Instantiate a field from a ClassReference"

	| field valueDict accessible atMaxDepth hasValueKey isValid |
	"Default: accessible if not specified"
	accessible := aDictionary at: #accessible ifAbsent: [ true ].
	atMaxDepth := aDictionary at: #atMaxDepth ifAbsent: [ false ].
	hasValueKey := aDictionary includesKey: #value.
	"Default: nil if not specified"
	valueDict := aDictionary at: #value ifAbsent: [ nil ].

	"Checking if the field has a valid construction with accessibility
	Should be either
	- accessible and not at max depth and have a value
	- inaccessible or at max depth, and dont have a value"
	isValid := atMaxDepth
		ifTrue: [ hasValueKey not or: [ valueDict isNil ] ]
		ifFalse: [ accessible = hasValueKey ].

	isValid ifFalse: [ Error signal: 'Field has not a valid construction' ].
	
	field := model newField
		 name: (aDictionary at: #name);
		 isAccessible: accessible;
		 isAtMaxDepth: atMaxDepth;
		 yourself.

	atMaxDepth ifFalse: [
		valueDict ifNil: [ field value: nil ] ifNotNil: [ field value: (self createValueWith: valueDict) ] ].
	^ field
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createParameters: anArray [
	"Instantiates all parameters of a method"

	^ anArray collect: [ :param |
			  self
				  createTypingFor: ((model newParameterNamed: (param at: #name))
						   isStub: true;
						   yourself)
				  with: (self ensureCreateType: (param at: #type)) ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createPrimitiveValue: aDictionary [
	"Instantiate a PrimitiveValue"

	| primVal |
	primVal := model newPrimitiveValue.
	self createTypingFor: primVal with: (self ensureCreatePrimitiveType: (aDictionary at: #type)).
	primVal value: (aDictionary at: #value).
	^ primVal
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createReceiver: aDictionary [
	"Instantiate the receiver of in a TraceMethod"

	aDictionary at: #reference ifPresent: [ :reference | ^ model newReceiver value: (self createValueReference: (aDictionary at: #reference)) ].
	aDictionary at: #primitiveValue ifPresent: [ :primitive | Error signal: 'Receiver should not be a primitiveType receiver value' ].
	Error signal: 'Unexcepted receiver value'
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createTraceMethod: aDictionary [
	"Instantiate an element of a trace"

	"NOTE : IT IS IMPORTANT TO FOLLOW THE STEPS
		1. Method
		2. Arguments
		3. Receiver
		BECAUSE THE JAVA EXTRACTOR NEED FOLLOW THIS EXACT ORDER TO CREATE ALREADY FOUND REFERENCES"

	| line |
	line := model newTraceMethod.

	aDictionary
		at: #method
		ifPresent: [ :methodDict | line method: (self ensureCreateMethod: methodDict) ]
		ifAbsent: [ Error signal: 'MethodCall has no method' ].

	self createArguments: (aDictionary at: #arguments) forTraceMethod: line.

	(aDictionary at: #receiver) ifNotNil: [ :receiver | line receiver: (self createReceiver: receiver) ].
	line method: (self ensureCreateMethod: (aDictionary at: #method)).

	"Linking this method and its parents, in both the static and dynamic model version"

	createdElements
		at: (aDictionary at: #parentId)
		ifPresent: [ :parent | "static"
				model newInvocation
					sender: parent method;
					addCandidate: line method.
				"dynamic"
				parent addChildren: line ]
		ifAbsent: [ "no parents, should only happens for the first method of the trace"
				((aDictionary at: #parentId) < 0 and: [ createdElements isEmpty ]) ifFalse: [
					self error: 'Element of id ' , (aDictionary at: #parentId) asString, ' does not exists' ] ].
			
	createdElements at: (aDictionary at: #id) put: line.
	^ line
]

{ #category : 'as yet unclassified' }
JavaTraceJsonReader >> createTypingFor: anObject with: type [

	^ anObject
		  typing: (model newEntityTyping declaredType: type);
		  yourself
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createValueReference: aDictionary [
	"Instantiate a ValueReference"

	| reference type uniqueId typeName |
	uniqueId := aDictionary at: #uniqueId.

	"Check alreadyFound case"
	(aDictionary at: #alreadyFound ifAbsent: [ false ]) ifTrue: [
			^ createdReference at: uniqueId ifAbsent: [
					  Error signal: 'The objectReference with ID: ' , uniqueId asString
						  , ' is indicated to be already found, but is not in the saved references' ] ].

	"Ensure no duplicate creation"
	reference := createdReference
		             at: uniqueId
		             ifPresent: [
				             Error signal:
					             'Trying to create an object with ID: ' , uniqueId asString
					             , ' while an existing ObjectReference already has this ID' ]
		             ifAbsentPut: [ (self instantiateReferenceEntityFrom: aDictionary) uniqueID: uniqueId ].

	"Fill reference"
	reference fillFrom: (aDictionary at: #refered) reader: self.



	type := self ensureCreateType: (aDictionary at: #type).

	self createTypingFor: reference with: type.

	^ reference
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> createValueWith: aDictionnary [
	"Choose which subTypes of a Value should be instantiated"

	"Looking for either a reference or a primitive type, if neither are present throw an error"

	aDictionnary at: #reference ifPresent: [ :reference | ^ self createValueReference: reference ].
	aDictionnary at: #primitiveValue ifPresent: [ :primitive | ^ self createPrimitiveValue: primitive ].
	Error signal: 'Unexcepted argument value'
]

{ #category : 'accessing' }
JavaTraceJsonReader >> defaultPackage [

	^ createdSourcesPackages at: '<Default Package>' ifAbsentPut: [
			  defaultPackage := (model newPackageNamed: '<Default Package>')
				                    isStub: true;
				                    yourself ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateClassNamed: aString [

	^ self ensureCreateInterfaceOrClassNamed: aString withType: FamixJavaClass
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateInterfaceNamed: aString [

	^ self ensureCreateInterfaceOrClassNamed: aString withType: FamixJavaInterface
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateInterfaceOrClassNamed: aString withType: aType [

	| baseString packageSequence rawClassName container name lastDollarIndex |
	"Strip array markers to normalize the base type string"
	baseString := aString removeSuffix: '[]'.

	"Fragment the string by package separators to isolate the raw class name"
	packageSequence := baseString splitOn: $..
	rawClassName := packageSequence last.

	"Locate the last nesting delimiter to prevent destructive fragmentation"
	lastDollarIndex := rawClassName lastIndexOf: $$.

	"A dollar sign at index 0 (absent) or 1 (e.g., $Proxy0) categorically proves this is NOT a nesting separator."
	lastDollarIndex <= 1
		ifTrue: [
				name := rawClassName.
				container := self ensureCreatePackageFromStringCollection: packageSequence allButLast ]
		ifFalse: [ "Valid inner type or anonymous class detected. Extract the strict short name"
				name := rawClassName copyFrom: lastDollarIndex + 1 to: rawClassName size.

				"Container is explicitly nullified. Inner types must be linked to their enclosing class, not a package"
				container := nil ].

	"Inject or retrieve from the registry, enforcing the configured container and stub status"
	^ createdTypes at: name ifAbsentPut: [
			  model add: ((aType named: name)
					   typeContainer: container;
					   isStub: true;
					   yourself) ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateMethod: aDictionary [

	^ (createdMethods at: ((aDictionary at: #parentType) at: #name) ifAbsentPut: [ Dictionary new ])
		  at: (aDictionary at: #signature)
		  ifAbsentPut: [ self instantiateMethodFrom: aDictionary ]
]

{ #category : 'accessing' }
JavaTraceJsonReader >> ensureCreatePackageFromStringCollection: aCollection [

	| currentParent |
	self flag: 'Simplify this method'.
	"if the collection is empty then return the default package"
	aCollection ifEmpty: [ ^ self defaultPackage ].

	"Search for the source package"
	currentParent := createdSourcesPackages at: aCollection first ifAbsentPut: [
			                 (model newPackageNamed: aCollection first)
				                 isStub: true;
				                 yourself ].

	"If we are in a source package, then return it now"
	aCollection size = 1 ifTrue: [ ^ currentParent ].

	"If in nested package create all and return the deepest one"
	aCollection allButFirst do: [ :each | currentParent := self ensureCreatePackageNamed: each withParent: currentParent ].
	^ currentParent
]

{ #category : 'accessing' }
JavaTraceJsonReader >> ensureCreatePackageNamed: aString withParent: aPackage [

	^ aPackage childEntities detect: [ :each | each name = aString ] ifNone: [
			  (model newPackageNamed: aString)
				  parentPackage: aPackage;
				  isStub: true;
				  yourself ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateParametricClassNamed: aString [

	^ self ensureCreateInterfaceOrClassNamed: aString withType: FamixJavaParametricClass
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreateParametricInterfaceNamed: aString [

	^ self ensureCreateInterfaceOrClassNamed: aString withType: FamixJavaParametricInterface
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> ensureCreatePrimitiveType: aString [
	"Instantiate a PrimitiveType if not already on the model"
	| name |
	name := aString removeSuffix: '[]'.
	^ createdTypes at: name ifAbsentPut: [
			  (model newPrimitiveTypeNamed: name)
				  isStub: true;
				  yourself ]
]

{ #category : 'as yet unclassified' }
JavaTraceJsonReader >> ensureCreateType: aCollection [

	| isParametric isInterface name anonymousParentType result parentType |
	aCollection isString ifTrue: [ ^ self ensureCreatePrimitiveType: aCollection ].
	aCollection isDictionary ifFalse: [
		self error: 'should either be a String for a primitive type or a dictionary for a class' ].

	isParametric := aCollection at: #isParametric ifAbsent: false.
	isInterface := aCollection at: #isInterface ifAbsent: false.
	name := aCollection at: #name.

	"Choose the right type"
	result := isInterface
		          ifTrue: [
				          isParametric
					          ifTrue: [ self ensureCreateParametricInterfaceNamed: name ]
					          ifFalse: [ self ensureCreateInterfaceNamed: name ] ]
		          ifFalse: [
				          isParametric
					          ifTrue: [ self ensureCreateParametricClassNamed: name ]
					          ifFalse: [ self ensureCreateClassNamed: name ] ].

	"If the class is an anonymous type, add its parent"
	anonymousParentType := aCollection at: #anonymousParentType ifAbsent: nil.

	anonymousParentType ifNotNil: [
			parentType := self ensureCreateType: anonymousParentType.

			parentType isInterface
				ifTrue: [
						FamixJavaImplementation new
							source: result;
							target: parentType;
							mooseModel: model ]
				ifFalse: [
						FamixJavaInheritance new
							source: result;
							target: parentType;
							mooseModel: model ] ].

	"If the type is an Inner type, add its typecontainer differently"
	aCollection at: #typeContainer ifPresent: [ :container | result typeContainer: (self ensureCreateType: container) ].

	^ result
]

{ #category : 'initialization' }
JavaTraceJsonReader >> initialize [

	createdReference := Dictionary new.
	createdPrimitives := Dictionary new.
	createdTypes := Dictionary new.
	createdMethods := Dictionary new.
	createdSourcesPackages := Dictionary new.
	createdElements := Dictionary new
]

{ #category : 'as yet unclassified' }
JavaTraceJsonReader >> instantiateMethodFrom: aDictionnary [

	| methodType method |
	methodType := self chooseMethodTypeFrom: aDictionnary.
	method := (model add: (methodType named: (aDictionnary at: #name))) isStub: true.

	method isClassSide: (aDictionnary at: #isClassSide).
	method parentType: (self ensureCreateType: (aDictionnary at: #parentType)).
	method signature: (aDictionnary at: #signature).

	(self createParameters: (aDictionnary at: #parameters)) do: [ :param | method addParameter: param ].
	^ method
]

{ #category : 'accessing' }
JavaTraceJsonReader >> instantiateReferenceEntityFrom: aDictionary [

	| refered |
	refered := aDictionary at: #refered.
	refered isDictionary ifTrue: [
			refered at: #fields ifPresent: [ :fields | ^ model newClassReference ].
			refered at: #elements ifPresent: [ :elements | ^ model newArrayReference ] ].

	refered isString ifTrue: [ ^ model newStringReference ].
	Error signal: 'Should either be String or dictionary'
]

{ #category : 'accessing' }
JavaTraceJsonReader >> model [
	^ model
]

{ #category : 'accessing' }
JavaTraceJsonReader >> model: aModel [

	model := aModel
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> read: json [
	"Instantiate the JavaCallStack model from a json object"

	| stack lines valueIndependents |
	json ifEmpty: [ Error signal: 'The json file is empty' ] ifNotEmpty: [
			model := FamixJTModel new
				         name: filename;
				         yourself.
			stack := model newTrace.

			valueIndependents := json at: #valueIndependents.
			lines := json at: #Lines.

			lines do: [ :line |
					valueIndependents ifTrue: [ createdReference := Dictionary new ].
					stack addTraceElement: (self createTraceMethod: line) ].
			"reset moose name to make sure no error appear"
			model entities do: #resetMooseName ]
]

{ #category : 'instance creation' }
JavaTraceJsonReader >> readFrom: aFileReference [
	"Read the file reference as a json file and start the import as a JavaCallStack model"

	| reader |
	filename := aFileReference basename.
	reader := NeoJSONReader on: aFileReference readStream.
	self read: reader next.
	reader close.

	^ model
]
