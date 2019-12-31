import reggae;

enum commonFlags = "-w -g -debug";

alias default_ = dubDefaultTarget!(
    CompilerFlags(commonFlags),
    LinkerFlags(),
    CompilationMode.module_,
);

alias ut = dubTestTarget!(
    CompilerFlags(commonFlags),
    LinkerFlags(),
    CompilationMode.module_,
);

mixin build!(default_, ut);
