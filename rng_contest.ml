
#use "topfind";;
#thread;;
#require "ketrew";;
open Nonstd
module String = Sosa.Native_string
let (//) = Filename.concat

let say fmt = ksprintf (Printf.printf "%s\n%!") fmt

let configuration =
  let getenv s =
    try Sys.getenv s with _ -> say "Missing variable: %S" s; exit 1 in
  object (self)
    method test_path = getenv "TEST_DIR"
    method host = Ketrew.EDSL.Host.parse (getenv "YARN_HOST")
    method dieharder_command =
      try Sys.getenv "DIEHARDER" with _ -> "dieharder"
    method quick_test =
      try Sys.getenv "QUICK_TEST" = "true" with _ -> false
    method to_string ~indentation =
      let indent = String.make indentation ' ' in
      List.map ~f:(fun (k,v) -> sprintf "%s- %s: %s" indent k v) [
        "Test-path", self#test_path;
        "Host", Ketrew_pure.Host.to_string_hum self#host;
        "Dieharder command", sprintf "`%s`" self#dieharder_command;
        "Run mode",
        (match self#quick_test with true -> "Quick-test" | false -> "Full-test");
      ] |> String.concat ~sep:"\n"

  end

let rm_path ~host path =
  let open  Ketrew.EDSL in
  let host = configuration#host in
  workflow_node without_product
    ~name:(sprintf "rm %s" (Filename.basename path))
    ~make:(
      daemonize ~using:`Python_daemon ~host
        Program.(
          shf "rm -fr %s" Filename.(quote path)
        )
    )

let make_ocaml_generator () =
  let code =
    {ocaml|
let () =
  Random.self_init ();
  while true do
    print_char Random.(int 256 |> char_of_int);
    flush stdout;
  done
|ocaml}
  in
  let open  Ketrew.EDSL in
  let host = configuration#host in
  let output = configuration#test_path // "ocaml_rng_generator" in
  workflow_node (single_file ~host output)
    ~name:(sprintf "build %s" (Filename.basename output))
    ~edges:[on_failure_activate (rm_path ~host output)]
    ~make:(
      daemonize ~using:`Python_daemon ~host
        Program.(
          shf "echo %s > %s.ml" Filename.(quote code) Filename.(quote output)
          && shf "ocamlopt %s.ml -o %s"
            Filename.(quote output) Filename.(quote output)
        )
    )

  
let generators = [
  `Command ("urandom", "cat /dev/urandom", []);
  begin
    let ocaml_random = make_ocaml_generator () in
    `Command ("ocaml-random", ocaml_random#product#path,
              [Ketrew.EDSL.depends_on ocaml_random])
  end;
]
let tests =
  if configuration#quick_test then
    [`Dieharder 0]
  else
    List.init 18 ~f:(fun i -> `Dieharder i)
    @ List.init 3 ~f:(fun i -> `Dieharder (100 + i))
    @ List.init 10 ~f:(fun i -> `Dieharder (200 + i))

  

let dieharder generator ~test =
  match generator with
  | `Command (generator_name, cmd, generator_edges) ->
    let open  Ketrew.EDSL in
    let host = configuration#host in
    let test_name, test_option =
      match test with
      | `All -> ("all", "-a")
      | `Number i -> (sprintf "T%d" i, sprintf "-d %d" i)
    in
    let name = sprintf "RNGC-%s-dieharder-%s" generator_name test_name in
    let output =
      configuration#test_path
      // sprintf "rngc-%s-%s.txt" generator_name test_name in
    let edges =
      generator_edges
      @ [
        on_failure_activate (rm_path ~host output)
      ] in
    workflow_node (single_file ~host output)
      ~edges ~name
      ~make:(
        yarn_distributed_shell ~host
          ~container_memory:(`GB 12)
          ~timeout:(`Seconds (60 * 60 * 24))
          ~application_name:name
          Program.(
            shf "%s | %s -g 200 %s > %s"
              cmd configuration#dieharder_command
              test_option Filename.(quote output)
          )
      )

let the_workflow =
  let open Ketrew.EDSL in
  let edges =
    List.concat_map generators ~f:(fun generator ->
        List.map tests ~f:(function
          | `Dieharder i ->
            depends_on (dieharder generator ~test:(`Number i))
          )
      ) in
  workflow_node without_product ~edges
    ~name:"RNG Contest: common ancestor"

let () =
  match Sys.argv |> Array.to_list |> List.tl_exn with
  | "view" :: [] ->
    say "Configuration:\n%s\nWorkflow:\n  %s"
      (configuration#to_string ~indentation:2)
      (Ketrew.EDSL.workflow_to_string
         ~ansi_colors:false
         ~indentation:4 the_workflow)
  | "run" :: [] ->
    Ketrew.Client.submit_workflow the_workflow
      ~add_tags:["RNG-contest"]
  | other ->
    say "Wrong command line: [%s]" (String.concat ~sep:"; " other);
    exit 2
