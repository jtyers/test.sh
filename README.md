# test.sh
Frustrated when your well-tested app is let down by much-harder-to-test scripts doing non-app tasks? Can't unit test your scripts because they're fiddling with things that existing unit test frameworks can't mock/stub out?

If your script calls binaries like `sudo` or `mount`, or changes files in special places like `/proc` or `/sys`, how do you create a reliable test harness without resorting to using a chroot, VM or container?

Enter `test.sh`.

`test.sh` is a shell script unit test and mocking framework. It lets you mock *anything* - any command or shell built-in. It tracks which mocked-out commands are called and the parameters passed so you can assert on those later.

Importantly, `test.sh` only supports testing shell *functions* right now, since that is how I structure my more complex shell scripts. But let's use a simple example to show you what `test.sh` can do.

**NOTE** `test.sh` is new. I use it in my own business. That said, use it but expect it to go wrong on you occasionally. Pull requests and reporting of issues very welcome.

## Requirements

`test.sh` requires [jq](https://github.com/stedolan/jq) and `bash` to run.

## Example
Suppose I have a function, `create_file()`, which performs a mount, creates a file, calls `sync`, and unmounts.

```bash
#!/bin/sh

# usage: create_file <device to mount> <mount point> <file name>
create_file() {
	local _dev=$1
	local _mp=$2
	local _fname=$3

	mount -o noatime,user $_dev $_mp

	echo 'test data' > $_mp/$_fname

	sync
	umount $_mp
}
```

Now to unit test it. (Aside: I like to structure my tests in a BDD-like *given*, *when*, *then* style, but you don't have to)

```bash
#!/usr/bin/env test.sh

setup() {
	source ./create_file.sh
}

testMountAndCreateFiles() {
	# given
	dummy_device="/tmp/test-sh-dummy-device"
	dummy_mountpoint="/tmp/test-sh-mp"
	dummy_fname="foobar"

	mkdir -p $dummy_device $dummy_mountpoint

	mock_cmd mount
	mock_cmd umount
	mock_cmd sync

	# when
	create_file $dummy_device $dummy_mountpoint $dummy_fname

	# then

	# check the file exists and contains the data we want
	assert_file_content $dummy_mountpoint/$dummy_fname 'test data'

	# check our mock commands are called as expected
	assert_called mount -o noatime,user $dummy_device $dummy_mountpoint
	assert_called sync
	assert_called umount $dummy_mountpoint
}
```

So, what's going on here?

We start with the `setup()` function, which is executed once before each test is run. You can do any setup you want here that applies to all tests. The minimum you need to do is *source your test file*. `test.sh` has no way of knowing the script you intend to test; thus you must source it here so that you can call its functions from your tests.

Following `setup()` are your test functions. In the example above all my test functions begin with `test...`, but you can change this.

First (in my *given* section), I set up a few pieces of test data and create the directories my script will expect. I then call `mock_cmd` for commands I want to mock; `mock_cmd` will create a shell function which does nothing, and name it after the command. The effect of this is that when my script calls `mount`, the mock function gets called and not the real `mount`. You can also pass simple statements to instruct the mock to do something; e.g. `mock_cmd mount echo mounted!`. `mock_cmd` will also automatically start tracking any calls that are made to the commands you've mocked, which we assert further on in the test.

In my *when* section I call the code I want to test, passing in my test data.

The *then* section is where I do my asserts. The asserts are nice and self-documenting where possible.
* `assert_file_content` does exactly that, allowing you to specify a string that `test.sh` looks for (it has to be an *exact* match; this method of asserting is best for small one-line files, such as files in `/proc`, PID files and so on).
* `assert_called` checks out mock to see if it was called with the arguments you specify. Notice how I passed in some fancy options to `mount`, and assert on those in the same line?

## Running your tests
`test.sh` can be run in one of two ways.

- Hashbang: use `#!/usr/bin/env test.sh` or `#!/path/to/test.sh` in the first line of your script
- Directly: run `/path/to/test.sh mytestfile`

## Change the name of your tests
By default `test.sh` looks for functions beginning with the word `test`. Change this using `test.sh -p <prefix> mytestfile`. e.g. `test.sh -p should mytestfile` will look for all functions in `mytestfile` beginning with the string `should` and execute them all.

## Testing order of calls
`assert_called` by default checks the *most recent* call to a command. You might have a command called several times that you want to assert on. For example, a script that, given a read-only file system, mounts it `rw`, writes a file and remounts `ro`:

```bash
#!/bin/sh

# usage: create_file <mount point> <file name>
create_file() {
	local _mp=$1
	local _fname=$2

	mount -o remount,rw $_mp

	echo 'test data' > $_mp/$_fname

	mount -o remount,ro $_mp
}
```

And the unit test:

```bash
#!/usr/bin/env test.sh

testRemountWriteAndRemountAgain() {
	# given
	dummy_mountpoint="/tmp/test-sh-mp"
	dummy_fname="foobar"

	mkdir -p $dummy_mountpoint

	mock_cmd mount

	# when
	create_file $dummy_mountpoint $dummy_fname

	# then

	# check the file exists and contains the data we want
	assert_file_content $dummy_mountpoint/$dummy_fname 'test data'

	# check our mock commands are called in order
	assert_called_n 0 mount -o remount,rw $dummy_mountpoint
	assert_called_n 1 mount -o remount,ro $dummy_mountpoint
}
```

In this example, instead of `assert_called` we use `assert_called_n`, aka "assert that X was called the nth time". Behind the scenes is an array starting at 0, so to assert against the first call, we specify `assert_called_n 0`, the second call `assert_called_n 1` and so on.

## Other asserts
I've added asserts as I've use `test.sh` on my own projects. So far there is:
* `assert_called`, `assert_called_n` - assert calls to mock commands created via `mock_cmd`
* `assert_file_content <file> <string>` - assert that `file` contains content `string`
* `assert_dir <path>` - check a path exists and is a directory
* `assert_file <path>` - check a path exists and is a file
* `assert_missing <path>` - check a path does *not* exist
