RNG Contest
===========

Ketrew pipeline that runs PRNG test suite(s) (for now just Dieharder).

Usage
-----

For now one needs a YARN cluster, the script is configured with environment
variables; some are required, some optional.


```shell
export TEST_DIR=$SHARED_FS/rng-contest-playground/   # A directory for the results, required
export YARN_HOST=named://My_YARN_Cluster$TEST_DIR/KT/   # Ketrew.EDSL.Host.parse URL, required
export DIEHARDER="LD_LIBRARY_PATH=$TEST_DIR $TEST_DIR/dieharder" # Optional, how to call `dieharder`
export QUICK_TEST=true   # Optional, if true, then run only `dieharder -d 0`

ocaml rng_contest.ml [view | run]  # Display or submit the workflow
```

With `$QUICK_TEST=true` the output looks like:

```
$ mk view
* RNG Contest: common ancestor
  * RNGC-urandom-dieharder-T0
    × rm rngc-urandom-T0.txt
  * RNGC-ocaml-random-dieharder-T0
    * build ocaml_rng_generator
      × rm ocaml_rng_generator
    × rm rngc-ocaml-random-T0.txt
```

