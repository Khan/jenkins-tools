// Delete a version of our application on App Engine.

@Library("kautils")
// Classes we use, under jenkins-jobs/src/.
import org.khanacademy.Setup;
// Vars we use, under jenkins-jobs/vars/.  This is just for documentation.
//import vars.exec
//import vars.kaGit
//import vars.notify
//import vars.withTimeout


new Setup(steps

).addStringParam(
    "VERSION",
    """<b>REQUIRED</b>. The names of the versions to delete, separated by
spaces. Must exactly match the name of an existing version (e.g.
"znd-170101-sean-znd-test 170101-1200-deadbeef1234")""",
    ""

).addStringParam(
    "MODULES",
    """The modules to delete, comma-separated.  By default we delete all the
"webapp" modules.""",
    ""

).apply();

currentBuild.displayName = "${currentBuild.displayName} (${params.VERSION})";


def verifyArgs() {
   if (!params.VERSION) {
      notify.fail("The VERSION parameter is required.");
   }
}


def deleteVersion() {
   withTimeout('15m') {
      kaGit.safeSyncToOrigin("git@github.com:Khan/webapp", "master");
      dir("webapp") {
         sh("make python_deps");
         def args = (["deploy/delete_gae_versions.py"]
                     // We need to cast because split() returns an Array and
                     // groovy wants a List, apparently.
                     + (params.VERSION.split(" ") as List));
         if (params.MODULES) {
            args += ["--modules", params.MODULES];
         }
         exec(args);
      }
   }
}


onMaster('30m') {
   notify([slack: [channel: '#1s-and-0s-deploys',
                sender: 'Mr Monkey',
                emoji: ':monkey_face:',
                when: ['FAILURE', 'UNSTABLE', 'ABORTED']],
        aggregator: [initiative: 'infrastructure',
                     when: ['SUCCESS', 'BACK TO NORMAL',
                            'FAILURE', 'ABORTED', 'UNSTABLE']]]) {
      verifyArgs();
      stage("Deleting") {
         deleteVersion();
      }
   }
}
