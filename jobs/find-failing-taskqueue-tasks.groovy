// A pipeline job to run the failing_taskqueue_tasks script.

@Library("kautils")
// Classes we use, under jenkins-jobs/src/.
import org.khanacademy.Setup;
//import vars.exec
//import vars.kaGit
//import vars.notify


new Setup(steps

).addStringParam(
   "SLACK_CHANNEL",
   "The slack channel to send our results, or empty string to disable.",
   "#bot-testing"

).apply();


onMaster('1h') {
      notify([slack: [channel: params.SLACK_CHANNEL,
                  sender: 'Taskqueue Totoro',
                  emoji: ':totoro:',
                  when: ['FAILURE', 'UNSTABLE', 'ABORTED']]]) {
      stage("Running script") {
         kaGit.safeSyncToOrigin("git@github.com:Khan/webapp", "master");
         dir("webapp") {
            sh("make python_deps");
            exec(["dev/tools/failing_taskqueue_tasks.py",
                  "--slack-channel=${params.SLACK_CHANNEL}"]);
         }
      }
   }
}
