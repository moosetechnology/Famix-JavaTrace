# FamixJavaTrace

This project offers a metamodel for Java traces, enabling dynamic analysis of Java applications directly within Moose.

This project can imports file created using [JavaTraceExtractor](https://github.com/moosetechnology/JavaTraceExtractor).

## Loading the project into Moose
To load FamixCallStack into a Moose image, execute the following code:
```Smalltalk
Metacello new githubUser: 'moosetechnology' project: 'Famix-JavaTrace' commitish: 'master' path: 'src';
	baseline: 'FamixJavaTrace';
	load.
```


## Usage

### Importing a Java Trace Model
You can import a trace in two ways:
#### 1. Programmatically
The file extension .cs is not strictly required, a .json would also work:
```smalltalk
file := '/Path/To/.../JDIOutput.tr' asFileReference.
model := JavaTraceJsonReader import: file.
```
#### 2. With drag and drops
Simply drag the JDIOutput.tr file onto your Moose image.  
**Note:** In this case, the file must have a .tr extension, otherwise, the import will fail.

