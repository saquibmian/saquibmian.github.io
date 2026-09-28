+++
date = "2017-03-28T19:59:00-04:00"
draft = false
title = "Using the TryGet pattern in C#"

description = "The TryGet pattern is a little gem scattered throughout C# APIs, but many developers might not notice it. Let's explore why it's so useful."
+++

The TryGet pattern is a little gem scattered throughout C# APIs, but many developers might not notice it. The general signature looks like this:

```csharp
bool TryGetSomething( SomeInput i, out Something s );
```

As you can tell from the signature, the method returns a `bool` and takes any number of input parameters, the last of which is always an output parameter. The name `TryGetSomething` implies that the method will attempt to _get_ Something (given input `i`), but that getting it may fail. 

When I call `TryGetSomething`, I can make certain assumptions about it:

1. If `TryGetSomething` returns true, `s` is a _valid_ value and can be used (where valid is specific to your domain). 
2. If `TryGetSomething` returns false, `s` is _not_ a valid value and cannot be used (its value is an implementation detail that you _cannot_ rely on).
3. `TryGetSomething` will _not_ throw an exception. For example, if I have a method named `TryGetGrade`, I do not expect any exceptions as it attempts to get the grade.

Here’s a real world example, accessing a dictionary:

```csharp
var dict = new Dictionary<long, IUser>();

// some code to load users

IUser user = null;
if( !dict.TryGetValue( SomeUserId, out user ) ) {
	// TryGetValue returned false, so we failed to get the user and `user` is not useful
	// error handling logic usually goes here
}
// `user` can be used safely here
```

In this example, we use `Dictionary<K, V>.TryGetValue` to try to extract a user from the dictionary given a user ID. If the ID doesn’t exist, the method returns `false` and we handle the case. Otherwise, the user is assigned to `user` and we can carry on.

## Implementing the TryGet pattern

Here’s a typical implementation of the TryGet pattern:

```csharp
bool TryGetOrganization( long orgId, out IOrganization org ) {
	if( !OrgExists( orgId ) ) {
		org = null;
		return false;
	}

	org = GetOrgOrDefault( orgId );
	return org != null;
}
```

In this hypothetical domain, `GetOrgOrDefault` returns `null` on failure. If it threw an exception on failure (and was called `GetOrg`) instead, our implementation looks a little different:

```csharp
bool TryGetOrganization( long orgId, out IOrganization org ) {
	if( !OrgExists( orgId ) ) {
		org = null;
		return false;
	}

	try {
		org = GetOrg( orgId );
		return true;
	} catch ( SomeGetOrgException e ) {
		org = null;
		return false;
	}
}
```

## When TryGet is confusing

Here’s a _confusing_ attempt at a TryGet method:

```csharp
string TryGetName( string name1, string name2, params string[] names ) {
	if( !string.IsNullOrEmpty( name1 ) ) {
		return name1;
	}
	if ( !string.IsNullOrEmpty( name2 ) ) {
		return name2;
	}
	
	return names.FirstOrDefault( n => !string.IsNullOrEmpty( n ) );
}
// used like this
var canonnicalName = TryGetName( userName, firstName, lastName );
```

This method is confusing because it doesn't actually implement the TryGet pattern at all. There is no notion of success or failure, and the method must document its behaviour to be useful. This method is better named `GetFirstNonNullName`. Developers expect that a method that is prefixed with `TryGet` follows the TryGet pattern. Naming is hard, but if done well it can make code easier to grasp.

## TryGet is actually TryVerb

You may have realized that the TryGet pattern can be _even further_ generalized. Here's an example:

```csharp
int userId = 0;
if( !int.TryParse( "169", out userId ) ) {
	// error handling logic here
}
// userId was successfully parsed, and we can use it
```

`int.TryParse` follows the rules of the TryVerb pattern. All TryVerb methods have the same behaviour: they return a success indicator and assign a valid output parameter in the success case.

The TryGet pattern is so useful that with C# 7 (which we don't use at D2L yet), Microsoft added the ability to declare out parameters inline, so that we can use them like this:

```csharp
if( int.TryParse( "169", out var userId ) ) {
	// call succeeded
	// `userId` is scoped to this block
}
// `userId` is out of scope here
// error handling logic is here instead
```