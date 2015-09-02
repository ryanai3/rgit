class Descriptions
  attr_accessor :init
  def initialize
    @init = {
        long_desc:
            "This command creates an empty Git repository - basically a .git "\
      "directory with subdirectories for objects, refs/heads, refs/tags, "\
      "and template files. "\
      "An initial HEAD file that references the HEAD of the master branch is "\
      " also created."\
      "\n\n"\
      "If the $GIT_DIR environment variable is set then it specifies a path "\
      "to use instead of ./.git for the base of the repository."\
      "\n\n"\
      "If the object storage directory is specified via the "\
      "$GIT_OBJECT_DIRECTORY environment variable then the sha1 directories "\
      "are created underneath - otherwise the default $GIT_DIR/objects "\
      "directory is used."\
      "\n\n"\
      "Running git init in an existing repository is safe. It will not"\
      "overwrite things that are already there. The primary reason for"\
      "rerunning git init is to pick up newly added templates (or to move"\
      "the repository to another place if --separate-git-dir is given).",
        quiet:
            "\n\t"\
      "Only print error and warning messages; all other output will be suppressed."\
      "\n\n",
        bare:
            "\n\t"\
      "Create a bare repository. If GIT_DIR environment is not set, "\
      "it is set to the current working directory."\
      "\n\n",
        separate_git_dir:
            "\n\t"\
      "Instead of initializing the repository as a directory to either "\
      "$GIT_DIR or ./.git/, create a text file there containing the path "\
      "to the actual "\
      "\n\t"\
      "repository. This file acts as filesystem-agnostic Git "\
      "symbolic link to the repository."\
      "\n\n\t"\
      "If this is reinitialization, "\
      "the repository will be moved to the specified path."\
      "\n\n",
        shared:
            "\n\t"\
      "Specify that the Git repository is to be shared amongst several users."\
      "This allows users belonging to the same group to push into that repository."\
      "\n\t"\
      "When specified, the config variable \"core.sharedRepository\" is set so that"\
      "files and directories under $GIT_DIR are created with the requested permissions."\
      "\n\t"\
      "When not specified, Git will use permissions reported by umask(2)."\
      "\n\n",
        template:
            "\n\t"\
      "Specify the directory from which templates will be used."\
      "(See the \"TEMPLATE DIRECTORY\" section below.)"\
      "\n\n",
    }
  end
end
