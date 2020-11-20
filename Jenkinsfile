#!groovy

import groovy.json.JsonOutput
import bcgov.GitHubHelper


// Notify stage status and pass to Jenkins-GitHub library
void notifyStageStatus (String name, String status) {

    echo scm.getUserRemoteConfigs()[0].getUrl()

    GitHubHelper.createCommitStatus(
        this,
        GitHubHelper.getPullRequestLastCommitId(this),
        status,
        "${env.BUILD_URL}",
        "Stage '${name}'",
        "Stage: ${name}"
    )
}


// Create deployment status and pass to Jenkins-GitHub library
void createDeploymentStatus (String suffix, String status, String stageUrl) {
    def ghDeploymentId = GitHubHelper.createDeployment(
        this,
        "pull/${env.CHANGE_ID}/head",
        [
            'environment':"${suffix}",
            'task':"deploy:pull:${env.CHANGE_ID}"
        ]
    )

    GitHubHelper.createDeploymentStatus(
        this,
        ghDeploymentId,
        "${status}",
        ['targetUrl':"https://${stageUrl}/gwells"]
    )

    if ('SUCCESS'.equalsIgnoreCase("${status}")) {
        echo "${suffix} deployment successful!"
    } else if ('PENDING'.equalsIgnoreCase("${status}")){
        echo "${suffix} deployment pending."
    }
}


// Print stack trace of error
@NonCPS
private static String stackTraceAsString(Throwable t) {
    StringWriter sw = new StringWriter();
    t.printStackTrace(new PrintWriter(sw));
    return sw.toString()
}


// OpenShift wrapper
def _openshift(String name, String project, Closure body) {
    script {
        openshift.withCluster() {
            openshift.withProject(project) {
                echo "Running Stage '${name}'"
                waitUntil {
                    notifyStageStatus (name, 'PENDING')
                    boolean isDone=false
                    try {
                        body()
                        isDone=true
                        notifyStageStatus(name, 'SUCCESS')
                        echo "Completed Stage '${name}'"
                    } catch (error){
                        notifyStageStatus(name, 'FAILURE')
                        echo "${stackTraceAsString(error)}"
                        def inputAction = input(
                            message: "This step (${name}) has failed. See related messages.",
                            ok: 'Confirm',
                            parameters: [
                                choice(
                                    name: 'action',
                                    choices: 'Re-run\nIgnore',
                                    description: 'What would you like to do?'
                                )
                            ]
                        )
                        if ('Ignore'.equalsIgnoreCase(inputAction)){
                            isDone=true
                        }
                    }
                    return isDone
                }
            }
        }
    }
}

// Functional test script
// Can be limited by assinging toTest var
def unitTestDjango (String stageName, String envProject, String envSuffix) {
    _openshift(env.STAGE_NAME, envProject) {
        def DB_target = envSuffix == "staging" ? "${appName}-pg12-${envSuffix}" : "${appName}-pg12-${envSuffix}-${prNumber}"
        def DB_newVersion = openshift.selector("dc", "${DB_target}").object().status.latestVersion
        def DB_pod = openshift.selector('pod', [deployment: "${DB_target}-${DB_newVersion}"])
        echo "Temporarily granting elevated DB rights"
        echo DB_target
        def db_ocoutput_grant = openshift.exec(
            DB_pod.objects()[0].metadata.name,
            "--",
            "bash -c '\
                psql -c \"ALTER USER \\\"\${PG_USER}\\\" WITH SUPERUSER;\" \
            '"
        )
        echo "Temporary DB grant results: "+ db_ocoutput_grant.actions[0].out

        def target = envSuffix == "staging" ? "${appName}-${envSuffix}" : "${appName}-${envSuffix}-${prNumber}"
        def newVersion = openshift.selector("dc", "${target}").object().status.latestVersion
        def pods = openshift.selector('pod', [deployment: "${target}-${newVersion}"])

        // Wait here and make sure the app pods are ready before running unit tests.
        // We wait for both pods to be ready so that we can execute the test command
        // on either one, without having to check which one was ready first.
        timeout(15) {
            pods.untilEach(2) {
                return it.object().status.containerStatuses.every {
                    it.ready
                }
            }
        }

        echo "Running Django unit tests"
        def ocoutput = openshift.exec(
            pods.objects()[0].metadata.name,
            "--",
            "bash -c '\
                cd /opt/app-root/src/backend; \
                python manage.py test \
            '"
        )
        echo "Django test results: "+ ocoutput.actions[0].out

        echo "Revoking ADMIN rights"
        def db_ocoutput_revoke = openshift.exec(
            DB_pod.objects()[0].metadata.name,
            "--",
            "bash -c '\
                psql -c \"ALTER USER \\\"\${PG_USER}\\\" WITH NOSUPERUSER;\" \
            '"
        )
        echo "DB Revocation results: "+ db_ocoutput_revoke.actions[0].out
    }
}


// API test function
def apiTest (String stageName, String stageUrl, String envSuffix) {
    _openshift(env.STAGE_NAME, toolsProject) {
        podTemplate(
            label: "nodejs-${appName}-${envSuffix}-${prNumber}",
            name: "nodejs-${appName}-${envSuffix}-${prNumber}",
            serviceAccount: 'jenkins',
            cloud: 'openshift',
            activeDeadlineSeconds: 1800,
            containers: [
                containerTemplate(
                    name: 'jnlp',
                    image: 'registry.access.redhat.com/openshift3/jenkins-agent-nodejs-8-rhel7',
                    resourceRequestCpu: '500m',
                    resourceLimitCpu: '800m',
                    resourceRequestMemory: '512Mi',
                    resourceLimitMemory: '1Gi',
                    activeDeadlineSeconds: '600',
                    podRetention: 'never',
                    workingDir: '/tmp',
                    command: '',
                    args: '${computer.jnlpmac} ${computer.name}',
                    envVars: [
                        envVar(
                            key:'BASE_URL',
                            value: "https://${stageUrl}/gwells"
                        ),
                        secretEnvVar(
                            key: 'GWELLS_API_TEST_USER',
                            secretName: 'apitest-secrets',
                            secretKey: 'username'
                        ),
                        secretEnvVar(
                            key: 'GWELLS_API_TEST_PASSWORD',
                            secretName: 'apitest-secrets',
                            secretKey: 'password'
                        ),
                        secretEnvVar(
                            key: 'GWELLS_API_TEST_AUTH_SERVER',
                            secretName: 'apitest-secrets',
                            secretKey: 'auth_server'
                        ),
                        secretEnvVar(
                            key: 'GWELLS_API_TEST_CLIENT_ID',
                            secretName: 'apitest-secrets',
                            secretKey: 'client_id'
                        ),
                        secretEnvVar(
                            key: 'GWELLS_API_TEST_CLIENT_SECRET',
                            secretName: 'apitest-secrets',
                            secretKey: 'client_secret'
                        )
                    ]
                )
            ]
        ) {
            node("nodejs-${appName}-${envSuffix}-${prNumber}") {
                checkout scm
                dir('tests/api-tests') {
                    sh 'npm install -g newman@4.6.1'
                    try {
                        sh """
                            newman run ./registries_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./registries_v2_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./wells_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./wells_v2_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./submissions_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./submissions_v2_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./aquifers_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                            newman run ./aquifers_v2_api_tests.json \
                                --global-var test_user=\$GWELLS_API_TEST_USER \
                                --global-var test_password=\$GWELLS_API_TEST_PASSWORD \
                                --global-var base_url=\$BASE_URL \
                                --global-var auth_server=\$GWELLS_API_TEST_AUTH_SERVER \
                                --global-var client_id=\$GWELLS_API_TEST_CLIENT_ID \
                                --global-var client_secret=\$GWELLS_API_TEST_CLIENT_SECRET \
                                -r cli,junit,html
                        """

                        if ("dev".equalsIgnoreCase("${envSuffix}")) {
                            sh """
                                newman run ./wells_search_api_tests.json \
                                --global-var base_url=\$BASE_URL \
                                -r cli,junit,html
                            """
                        }

                    } finally {
                        junit 'newman/*.xml'
                        publishHTML (
                          target: [
                              allowMissing: false,
                              alwaysLinkToLastBuild: false,
                              keepAll: true,
                              reportDir: 'newman',
                              reportFiles: 'newman*.html',
                              reportName: "API Test Report"
                          ]
                        )
                        stash includes: 'newman/*.xml', name: 'api-tests'
                    }
                }
            }
        }
    }
    return true
}


def zapTests (String stageName, String envUrl, String envSuffix) {
    _openshift(env.STAGE_NAME, toolsProject) {
        def podName = envSuffix == "dev" ? "zap-${envSuffix}-${prNumber}" : "zap-${envSuffix}"
        podTemplate(
            label: "${podName}",
            name: "${podName}",
            serviceAccount: "jenkins",
            cloud: "openshift",
            containers: [
                containerTemplate(
                    name: 'jnlp',
                    image: 'docker-registry.default.svc:5000/openshift/jenkins-slave-zap',
                    resourceRequestCpu: '1',
                    resourceLimitCpu: '1',
                    resourceRequestMemory: '2Gi',
                    resourceLimitMemory: '2Gi',
                    activeDeadlineSeconds: '600',
                    workingDir: '/home/jenkins',
                    command: '',
                    args: '${computer.jnlpmac} ${computer.name}',
                    envVars: [
                        envVar(
                            key:'BASE_URL',
                            value: "https://${envUrl}/gwells"
                        )
                    ]
                )
            ]
        ) {
            node("${podName}") {
                checkout scm
                sh (
                    script: "/zap/zap-baseline.py -r index.html -t $BASE_URL",
                    returnStatus: true
                )

                publishHTML(
                    target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: false,
                        keepAll: true,
                        reportDir: '/zap/wrk',
                        reportFiles: 'index.html',
                        reportName: 'ZAP Baseline Scan',
                        reportTitles: 'ZAP Baseline Scan'
                    ]
                )
            }
        }
    }
    return true
}


// Database backup
def dbBackup (String envProject, String envSuffix) {
    def dcName = envSuffix == "dev" ? "${appName}-pg12-${envSuffix}-${prNumber}" : "${appName}-pg12-${envSuffix}"
    def dumpDir = "/pgdata/deployment-backups"
    def dumpName = "${envSuffix}-\$( date +%Y-%m-%d-%H%M ).dump"
    def dumpOpts = "--no-privileges --no-tablespaces --schema=public --exclude-table=spatial_ref_sys"
    def dumpTemp = "/tmp/unverified.dump"
    int maxBackups = 10

    // Dump to temporary file
    sh "oc rsh -n ${envProject} dc/${dcName} bash -c ' \
        pg_dump -U \${PG_USER} -d \${PG_DATABASE} -Fc -f ${dumpTemp} ${dumpOpts} \
    '"

    // Verify dump size is at least 1M
    int sizeAtLeast1M = sh (
        script: "oc rsh -n ${envProject} dc/${dcName} bash -c ' \
            du --threshold=1M ${dumpTemp} | wc -l \
        '",
        returnStdout: true
    )
    assert sizeAtLeast1M == 1

    // Restore (schema only, w/ extensions) to temporary db
    // note: command needs to be updated.
    // See Jira ticket WATER-1163.
    // sh """
    //     oc rsh -n ${envProject} dc/${dcName} bash -c ' \
    //         set -e; \
    //         psql -c "DROP DATABASE IF EXISTS db_verify"; \
    //         createdb db_verify; \
    //         psql -d db_verify -c "CREATE EXTENSION IF NOT EXISTS postgis;"; \
    //         psql -d db_verify -c "COMMIT;"; \
    //         pg_restore -U postgres -d db_verify -e --schema-only ${dumpTemp}; \
    //         psql -c "DROP DATABASE IF EXISTS db_verify"
    //     '
    // """

    // Store verified dump
    sh "oc rsh -n ${envProject} dc/${dcName} bash -c ' \
        mkdir -p ${dumpDir}; \
        mv ${dumpTemp} ${dumpDir}/${dumpName}; \
        ls -lh ${dumpDir} \
    '"

    // Database purge
    sh "oc rsh -n ${envProject} dc/${dcName} bash -c \" \
            find ${dumpDir} -name *.dump -printf '%Ts\t%p\n' \
                | sort -nr | cut -f2 | tail -n +${maxBackups} | xargs rm 2>/dev/null \
                || echo 'No extra backups to remove' \
    \""
}

pipeline {
    environment {
        // Project-wide settings - app name, repo
        appName = "gwells"
        repository = 'https://www.github.com/bcgov/gwells.git'
        platformEnv = "${OCP_PLATFORM ?: '3'}"

        // prNumber is the pull request number e.g. 'pr-4'
        prNumber = "${env.JOB_BASE_NAME}".toLowerCase()

        // toolsProject is where images are built
        toolsProject = "${APP_TOOLS_NAMESPACE ?: "moe-gwells-tools"}"

        // devProject is the project where individual development environments are spun up
        devProject = "${APP_DEV_NAMESPACE ?: "moe-gwells-dev"}"
        devSuffix = "dev"
        devAppName = "${appName}-${devSuffix}-${prNumber}"
        devHost = "${devAppName}.pathfinder.gov.bc.ca"

        // stagingProject contains the test deployment. The test image is a candidate for promotion to prod.
        stagingProject = "${APP_STAGING_NAMESPACE ?: "moe-gwells-test"}"
        stagingSuffix = "staging"
        stagingHost = "gwells-staging.pathfinder.gov.bc.ca"

        // prodProject is the prod deployment.
        // TODO: New production images can be deployed by tagging an existing "test" image as "prod".
        prodProject = "${APP_PROD_NAMESPACE ?: "moe-gwells-prod"}"
        prodSuffix = "production"
        prodHost = "gwells-prod.pathfinder.gov.bc.ca"

        // name of the provisioned PVC claim for NFS backup storage
        // this will not be created during the pipeline; it must be created
        // before running the production pipeline.
        nfsProdBackupPVC = "bk-moe-gwells-prod-0z6f0qq0k2fz"
        nfsStagingBackupPVC = "bk-moe-gwells-test-dcog9cfksxat"

        // name of the PVC where documents are stored (e.g. Minio PVC)
        // this should be the same across all environments.
        minioDataPVC = "minio-data-vol"


        templateDir = "${OCP_PLATFORM == 4 ? 'openshift/ocp4' : 'openshift' }"

    }
    agent any
    stages {
        // the Start Pipeline stage will process and apply OpenShift build templates which will create
        // buildconfigs and an imagestream for built images.
        // each pull request gets its own buildconfig but all new builds are pushed to a single imagestream,
        // to be tagged with the pull request number.
        // e.g.:  gwells-app:pr-999
        stage('ALL - Prepare Templates') {
            steps {
                script {
                    echo "Starting deployment to OCP platform:   ${OCP_PLATFORM ?: '3'}"
                    echo "Cancelling previous builds..."
                    timeout(10) {
                        abortAllPreviousBuildInProgress(currentBuild)
                    }
                    echo "Previous builds cancelled"

                    _openshift(env.STAGE_NAME, toolsProject) {
                        //  - variable substitution
                        def buildtemplate = openshift.process("-f",
                            "${templateDir}/backend.bc.json",
                            "ENV_NAME=${devSuffix}",
                            "NAME_SUFFIX=-${devSuffix}-${prNumber}",
                            "APP_IMAGE_TAG=${prNumber}",
                            "SOURCE_REPOSITORY_URL=${repository}",
                            "SOURCE_REPOSITORY_REF=pull/${CHANGE_ID}/head"
                        )

                        // Apply oc list objects
                        //  - add docker image reference as tag in gwells-application
                        //  - create build config
                        echo "Preparing backend imagestream and buildconfig"
                        openshift.apply(buildtemplate)
                    }
                }
            }
        }


        // the Build stage builds files; an image will be outputted to the app's imagestream,
        // using the source-to-image (s2i) strategy. See /app/.s2i/assemble for image build script
        stage('ALL - Build') {
            steps {
                script {
                    _openshift(env.STAGE_NAME, toolsProject) {
                        echo "Running unit tests and building images..."
                        echo "This may take several minutes. Logs are not forwarded to Jenkins by default (at this time)."
                        echo "Additional logs can be found by monitoring builds in ${toolsProject}"

                        // Select appropriate buildconfig
                        def appBuild = openshift.selector("bc", "${devAppName}")
                        echo "Building"
                        appBuild.startBuild("--wait").logs("-f")
                    }
                }
            }
        }

        // the Deploy to Dev stage creates a new dev environment for the pull request (if necessary), tagging
        // the newly built application image into that environment.  This stage monitors the newest deployment
        // for pods/containers to report back as ready.
        stage('DEV - Deploy') {
            when {
                expression { env.CHANGE_TARGET != 'master' }
            }
            steps {
                script {
                    _openshift(env.STAGE_NAME, devProject) {
                        // Process postgres deployment config (sub in vars, create list items)
                        echo "Processing database deployment (using folder ${templateDir}"
                        def deployDBTemplate = openshift.process("-f",
                            "${templateDir}/postgresql.dc.yml",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${devSuffix}-${prNumber}",
                            "IMAGE_STREAM_NAMESPACE=${devProject}",
                            "IMAGE_STREAM_NAME=crunchy-postgres-gis",
                            "NAME_SUFFIX=-${devSuffix}-${prNumber}",
                            "POSTGRESQL_DATABASE=gwells",
                            "VOLUME_CAPACITY=1Gi",
                            "STORAGE_CLASS=netapp-file-standard",
                            "REQUEST_CPU=200m",
                            "REQUEST_MEMORY=512Mi",
                            "LIMIT_CPU=500m",
                            "LIMIT_MEMORY=1Gi"
                        )

                        // Process postgres deployment config (sub in vars, create list items)
                        echo "Processing deployment config for pull request ${prNumber}"
                        def deployTemplate = openshift.process("-f",
                            "${templateDir}/backend.dc.json",
                            "ENV_NAME=${devSuffix}",
                            "HOST=${devHost}",
                            "NAME_SUFFIX=-${devSuffix}-${prNumber}"
                        )

                        echo "Processing deployment config for tile server"
                        def pgtileservTemplate = openshift.process("-f",
                            "${templateDir}/pg_tileserv/pg_tileserv.dc.yaml",
                            "NAME_SUFFIX=-${devSuffix}-${prNumber}",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${devSuffix}-${prNumber}",
                            "HOST=${devHost}",
                        )

                        // some objects need to be copied from a base secret or configmap
                        // these objects have an annotation "as-copy-of" in their object spec (e.g. an object in backend.dc.json)
                        echo "Creating configmaps and secrets objects"
                        List newObjectCopies = []

                        for (o in (deployTemplate + deployDBTemplate)) {

                            // only perform this operation on objects with 'as-copy-of'
                            def sourceName = o.metadata && o.metadata.annotations && o.metadata.annotations['as-copy-of']
                            if (sourceName && sourceName.length() > 0) {
                                def selector = openshift.selector("${o.kind}/${sourceName}")
                                if (selector.count() == 1) {

                                    // create a copy of the object and add it to the new list of objects to be applied
                                    Map copiedModel = selector.object()
                                    copiedModel.metadata.name = o.metadata.name
                                    copiedModel.metadata.remove('annotations')
                                    copiedModel.metadata.remove('creationTimestamp')
                                    copiedModel.metadata.remove('resourceVersion')
                                    copiedModel.metadata.remove('selfLink')
                                    copiedModel.metadata.remove('uid')
                                    echo "[as-copy-of] Copying ${o.kind} ${o.metadata.name}"
                                    newObjectCopies.add(copiedModel)
                                }
                            }
                        }

                        echo "Applying deployment config for pull request ${prNumber} on ${devProject}"

                        // apply the templates, which will create new objects or modify existing ones as necessary.
                        // the copies of base objects (secrets, configmaps) are also applied.
                        openshift.apply(pgtileservTemplate).label(['app':"${devAppName}", 'app-name':"${appName}", 'env-name':"${devSuffix}"], "--overwrite")

                        openshift.apply(deployTemplate).label(['app':"${devAppName}", 'app-name':"${appName}", 'env-name':"${devSuffix}"], "--overwrite")
                        openshift.apply(deployDBTemplate).label(['app':"${devAppName}", 'app-name':"${appName}", 'env-name':"${devSuffix}"], "--overwrite")
                        openshift.apply(newObjectCopies).label(['app':"${devAppName}", 'app-name':"${appName}", 'env-name':"${devSuffix}"], "--overwrite")
                        echo "Successfully applied deployment configs for ${prNumber}"

                        // promote the newly built image to DEV
                        echo "Tagging new image to DEV imagestream."
                        openshift.tag("${toolsProject}/gwells-application:${prNumber}", "${devProject}/${devAppName}:dev")  // todo: clean up labels/tags

                        // post a notification to Github that this pull request is being deployed
                        createDeploymentStatus(devSuffix, 'PENDING', devHost)

                        // monitor the deployment status and wait until deployment is successful
                        echo "Waiting for deployment to dev..."
                        def newVersion = openshift.selector("dc", "${devAppName}").object().status.latestVersion
                        def pods = openshift.selector('pod', [deployment: "${devAppName}-${newVersion}"])

                        // wait until each container in this deployment's pod reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }

                        def pgtileservVersion = openshift.selector("dc", "pgtileserv-${devSuffix}-${prNumber}").object().status.latestVersion
                        def pgtileservPods = openshift.selector('pod', [deployment: "pgtileserv-${devSuffix}-${prNumber}-${newVersion}"])

                        // wait until each container in this deployment's pod reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }



                        // Report a pass to GitHub
                        createDeploymentStatus(devSuffix, 'SUCCESS', devHost)
                    }
                }
            }
        }

        // the Django Unit Tests stage runs backend unit tests using a test DB that is
        // created and destroyed afterwards.
        stage('DEV - Django Unit Tests') {
            when {
                expression { env.CHANGE_TARGET != 'master' }
            }
            steps {
                script {
                    def result = unitTestDjango (env.STAGE_NAME, devProject, devSuffix)
                }
            }
        }


        stage('DEV - Load Fixtures') {
            when {
                expression { env.CHANGE_TARGET != 'master' }
            }
            steps {
                script {
                    _openshift(env.STAGE_NAME, devProject) {
                        def newVersion = openshift.selector("dc", "${devAppName}").object().status.latestVersion
                        def pods = openshift.selector('pod', [deployment: "${devAppName}-${newVersion}"])

                        echo "Loading fixtures"
                        def ocoutput = openshift.exec(
                            pods.objects()[0].metadata.name,
                            "--",
                            "bash -c '\
                                cd /opt/app-root/src/backend; \
                                ./load_fixtures.sh all \
                            '"
                        )
                        echo "Load Fixtures results: "+ ocoutput.actions[0].out

                        openshift.exec(
                            pods.objects()[0].metadata.name,
                            "--",
                            "bash -c '\
                                cd /opt/app-root/src/backend; \
                                python manage.py createinitialrevisions \
                            '"
                        )
                    }
                }
            }
        }


        stage('DEV - API Tests') {
            when {
                expression { env.CHANGE_TARGET != 'master' }
            }
            steps {
                script {
                    def result = apiTest ('DEV - API Tests', devHost, devSuffix)
                }
            }
        }



        stage('STAGING - Backup') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    echo "backing up staging environment before deploying"
                    dbBackup (stagingProject, stagingSuffix)
                }
            }
        }

        // the Promote to Test stage allows approving the tagging of the newly built image into the test environment,
        // which will trigger an automatic deployment of that image.
        // The deployment configs in the openshift folder are applied first in case there are any changes to the templates.
        // this stage should only occur when the pull request is being made against the master branch.
        stage('STAGING - Deploy') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    _openshift(env.STAGE_NAME, stagingProject) {
                        echo "Preparing..."

                        // Process db and app template into list objects
                        // TODO: Match docker-compose image from moe-gwells-tools
                        echo "Updating staging deployment..."
                        def deployDBTemplate = openshift.process("-f",
                            "${templateDir}/postgresql.dc.yml",
                            "NAME_SUFFIX=-${stagingSuffix}",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${stagingSuffix}",
                            "IMAGE_STREAM_NAMESPACE=${stagingProject}",
                            "IMAGE_STREAM_NAME=crunchy-postgres-gis",
                            "IMAGE_STREAM_VERSION=centos7-12.2-4.2.2",
                            "POSTGRESQL_DATABASE=gwells",
                            "VOLUME_CAPACITY=20Gi",
                            "STORAGE_CLASS=netapp-file-standard",
                            "REQUEST_CPU=400m",
                            "REQUEST_MEMORY=2Gi",
                            "LIMIT_CPU=400m",
                            "LIMIT_MEMORY=2Gi"
                        )

                        def deployTemplate = openshift.process("-f",
                            "${templateDir}/backend.dc.json",
                            "NAME_SUFFIX=-${stagingSuffix}",
                            "ENV_NAME=${stagingSuffix}",
                            "HOST=${stagingHost}",
                            "CPU_REQUEST=500m",
                            "CPU_LIMIT=2",
                        )


                        echo "Processing deployment config for tile server"
                        def pgtileservTemplate = openshift.process("-f",
                            "${templateDir}/pg_tileserv/pg_tileserv.dc.yaml",
                            "NAME_SUFFIX=-${stagingSuffix}",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${stagingSuffix}",
                            "IMAGE_TAG=20200610",
                            "HOST=${stagingHost}",
                        )

                        // some objects need to be copied from a base secret or configmap
                        // these objects have an annotation "as-copy-of" in their object spec (e.g. an object in backend.dc.json)
                        echo "Creating configmaps and secrets objects"
                        List newObjectCopies = []

                        // todo: refactor to explicitly copy the objects we need
                        for (o in (deployTemplate + deployDBTemplate)) {

                            // only perform this operation on objects with 'as-copy-of'
                            def sourceName = o.metadata && o.metadata.annotations && o.metadata.annotations['as-copy-of']
                            if (sourceName && sourceName.length() > 0) {

                                def selector = openshift.selector("${o.kind}/${sourceName}")
                                if (selector.count() == 1) {
                                    // create a copy of the object and add it to the new list of objects to be applied
                                    Map copiedModel = selector.object()
                                    copiedModel.metadata.name = o.metadata.name
                                    echo "Copying ${o.kind} ${o.metadata.name}"
                                    newObjectCopies.add(copiedModel)
                                }
                            }
                        }

                        openshift.apply(deployDBTemplate).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        // apply the templates, which will create new objects or modify existing ones as necessary.
                        // the copies of base objects (secrets, configmaps) are also applied.
                        echo "Applying deployment config for pull request ${prNumber} on ${stagingProject}"

                        openshift.apply(pgtileservTemplate).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        openshift.apply(deployTemplate).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        openshift.apply(newObjectCopies).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        echo "Successfully applied TEST deployment config"

                        // promote the newly built image to DEV
                        echo "Tagging new image to TEST imagestream."

                        // Application/database images are tagged in the tools imagestream as the new test/prod image
                        openshift.tag(
                            "${toolsProject}/gwells-application:${prNumber}",
                            "${toolsProject}/gwells-application:${stagingSuffix}"
                        )  // todo: clean up labels/tags
                        // openshift.tag("${toolsProject}/gwells-postgresql:staging", "${toolsProject}/gwells-postgresql:${stagingSuffix}")

                        // Images are then tagged into the target environment namespace (test or prod)
                        openshift.tag(
                            "${toolsProject}/gwells-application:${stagingSuffix}",
                            "${stagingProject}/gwells-${stagingSuffix}:${stagingSuffix}"
                        )  // todo: clean up labels/tags

                        createDeploymentStatus(stagingSuffix, 'PENDING', stagingHost)

                        // Create cronjob for well export
                        def exportWellCronTemplate = openshift.process("-f",
                            "${templateDir}/export.cj.json",
                            "ENV_NAME=${stagingSuffix}",
                            "PROJECT=${stagingProject}",
                            "TAG=${stagingSuffix}",
                            "NAME=export",
                            "COMMAND=export",
                            "SCHEDULE='30 3 * * *'"
                        )
                        openshift.apply(exportWellCronTemplate).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        // Create cronjob for licence import
                        def importLicencesCronjob = openshift.process("-f",
                            "${templateDir}/jobs/import-licences/import-licences.cj.json",
                            "ENV_NAME=${stagingSuffix}",
                            "PROJECT=${stagingProject}",
                            "TAG=${stagingSuffix}",
                            "NAME=licences",
                            "COMMAND=import_licences",
                            "SCHEDULE='40 3 * * *'"
                        )
                        openshift.apply(importLicencesCronjob).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        // Create cronjob for aquifer demand calc update
                        def importUpdateAquiferCronjob = openshift.process("-f",
                            "${templateDir}/jobs/update-aquifer/update-aquifer.cj.json",
                            "ENV_NAME=${stagingSuffix}",
                            "PROJECT=${stagingProject}",
                            "TAG=${stagingSuffix}",
                            "NAME=demand",
                            "COMMAND=update_demand",
                            "SCHEDULE='50 3 * * *'"
                        )
                        openshift.apply(importUpdateAquiferCronjob).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        // Create cronjob for databc export
                        def exportDataBCTemplate = openshift.process("-f",
                            "${templateDir}/export.cj.json",
                            "ENV_NAME=${stagingSuffix}",
                            "PROJECT=${stagingProject}",
                            "TAG=${stagingSuffix}",
                            "NAME=export-databc",
                            "COMMAND=export_databc",
                            "SCHEDULE='0 4 * * *'"
                        )
                        openshift.apply(exportDataBCTemplate).label(
                            [
                                'app':"gwells-${stagingSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${stagingSuffix}"
                            ],
                            "--overwrite"
                        )

                        // automated minio backup
                        def docBackupCronjob = openshift.process("-f",
                            "${templateDir}/jobs/minio-backup/minio-backup.cj.yaml",
                            "NAME_SUFFIX=${stagingSuffix}",
                            "NAMESPACE=${stagingProject}",
                            "VERSION=v1.0.0",
                            "SCHEDULE='15 3 * * *'",
                            "DEST_PVC=gwells-pg12-backup",
                            "SOURCE_PVC=${minioDataPVC}"
                        )

                        openshift.apply(docBackupCronjob)

                        // automated database backup
                        def dbNFSBackup = openshift.process("-f",
                            "${templateDir}/jobs/postgres-backup-nfs/postgres-backup.cj.yaml",
                            "NAMESPACE=${stagingProject}",
                            "TAG_NAME=v12.0.0",
                            "TARGET=gwells-pg12-staging",
                            "PVC_NAME=gwells-pg12-backup",
                            "SCHEDULE='30 2 * * *'",
                            "JOB_NAME=postgres-nfs-backup",
                            "DAILY_BACKUPS=2",
                            "WEEKLY_BACKUPS=1",
                            "MONTHLY_BACKUPS=1"
                        )
                        openshift.apply(dbNFSBackup)

                        // monitor the deployment status and wait until deployment is successful
                        echo "Waiting for deployment to STAGING..."
                        def newVersion = openshift.selector("dc", "gwells-${stagingSuffix}").object().status.latestVersion
                        def pods = openshift.selector('pod', [deployment: "gwells-${stagingSuffix}-${newVersion}"])

                        // wait until at least one pod reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }

                        def pgtileservVersion = openshift.selector("dc", "pgtileserv-${stagingSuffix}").object().status.latestVersion
                        def pgtileservPods = openshift.selector('pod', [deployment: "pgtileserv-${stagingSuffix}-${newVersion}"])

                        // wait until each container in this deployment's pod reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }

                        createDeploymentStatus(stagingSuffix, 'SUCCESS', stagingHost)
                    }
                }
            }
        }


        // the Django Unit Tests stage runs backend unit tests using a test DB that is
        // created and destroyed afterwards.
        stage('Staging - Django Unit Tests') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    def result = unitTestDjango (env.STAGE_NAME, stagingProject, stagingSuffix)
                }
            }
        }


        stage('STAGING - API Tests') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    def result = apiTest ('STAGING - API Tests', stagingHost, stagingSuffix)
                }
            }
        }

        stage('PROD - Backup') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    dbBackup (prodProject, prodSuffix)
                }
            }
        }


        stage('PROD - Deploy') {
            when {
                expression { env.CHANGE_TARGET == 'master' }
            }
            steps {
                script {
                    input "Deploy to production?"
                    echo "Updating production deployment..."

                    _openshift(env.STAGE_NAME, prodProject) {

                        // Pre-deployment database backup
                        def dbBackupResult = dbBackup (prodProject, prodSuffix)

                        def deployDBTemplate = openshift.process("-f",
                            "${templateDir}/postgresql.dc.yml",
                            "NAME_SUFFIX=-${prodSuffix}",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${prodSuffix}",
                            "IMAGE_STREAM_NAMESPACE=${prodProject}",
                            "IMAGE_STREAM_NAME=crunchy-postgres-gis",
                            "IMAGE_STREAM_VERSION=centos7-12.2-4.2.2",
                            "POSTGRESQL_DATABASE=gwells",
                            "STORAGE_CLASS=netapp-file-standard",
                            "VOLUME_CAPACITY=40Gi",
                            "REQUEST_CPU=800m",
                            "REQUEST_MEMORY=4Gi",
                            "LIMIT_CPU=2",
                            "LIMIT_MEMORY=4Gi"
                        )

                        def deployTemplate = openshift.process("-f",
                            "${templateDir}/backend.dc.json",
                            "NAME_SUFFIX=-${prodSuffix}",
                            "ENV_NAME=${prodSuffix}",
                            "HOST=${prodHost}",
                            "CPU_REQUEST=1",
                            "CPU_LIMIT=2",
                            "MEMORY_REQUEST=1Gi",
                            "MEMORY_LIMIT=2Gi"
                        )

                        echo "Processing deployment config for tile server"
                        def pgtileservTemplate = openshift.process("-f",
                            "${templateDir}/pg_tileserv/pg_tileserv.dc.yaml",
                            "NAME_SUFFIX=-${prodSuffix}",
                            "DATABASE_SERVICE_NAME=gwells-pg12-${prodSuffix}",
                            "IMAGE_TAG=20200610",
                            "HOST=${prodHost}",
                        )

                        // some objects need to be copied from a base secret or configmap
                        // these objects have an annotation "as-copy-of" in their object spec (e.g. an object in backend.dc.json)
                        echo "Creating configmaps and secrets objects"
                        List newObjectCopies = []

                        for (o in (deployTemplate + deployDBTemplate)) {

                            // only perform this operation on objects with 'as-copy-of'
                            def sourceName = o.metadata && o.metadata.annotations && o.metadata.annotations['as-copy-of']
                            if (sourceName && sourceName.length() > 0) {
                                def selector = openshift.selector("${o.kind}/${sourceName}")
                                if (selector.count() == 1) {

                                    // create a copy of the object and add it to the new list of objects to be applied
                                    Map copiedModel = selector.object()
                                    copiedModel.metadata.name = o.metadata.name
                                    echo "Copying ${o.kind} ${o.metadata.name}"
                                    newObjectCopies.add(copiedModel)
                                }
                            }
                        }

                        // apply the templates, which will create new objects or modify existing ones as necessary.
                        // the copies of base objects (secrets, configmaps) are also applied.
                        echo "Applying deployment config for pull request ${prNumber} on ${prodProject}"

                        openshift.apply(deployDBTemplate).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        openshift.apply(pgtileservTemplate).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        openshift.apply(deployTemplate).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        openshift.apply(newObjectCopies).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )


                        echo "Successfully applied production deployment config"

                        // promote the newly built image to DEV
                        echo "Tagging new image to production imagestream."

                        // Application/database images are tagged in the tools imagestream as the new prod image
                        openshift.tag(
                            "${toolsProject}/gwells-application:${prNumber}",
                            "${toolsProject}/gwells-application:${prodSuffix}"
                        )  // todo: clean up labels/tags

                        // TODO: determine best way to manage database images (at the moment they never change, but we don't want an unforeseen change to impact prod)
                        // openshift.tag("${toolsProject}/gwells-postgresql:prod", "${toolsProject}/gwells-postgresql:${prodSuffix}")

                        // Images are then tagged into the target environment namespace (prod)
                        openshift.tag(
                            "${toolsProject}/gwells-application:${prodSuffix}",
                            "${prodProject}/gwells-${prodSuffix}:${prodSuffix}"
                        )  // todo: clean up labels/tags


                        createDeploymentStatus(prodSuffix, 'PENDING', prodHost)

                        // Create cronjob for well export
                        def exportWellCronTemplate = openshift.process("-f",
                            "${templateDir}/export.cj.json",
                            "ENV_NAME=${prodSuffix}",
                            "PROJECT=${prodProject}",
                            "TAG=${prodSuffix}",
                            "NAME=export",
                            "COMMAND=export",
                            "SCHEDULE='30 3 * * *'"
                        )
                        openshift.apply(exportWellCronTemplate).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        // Create cronjob for databc export
                        def exportDataBCCronTemplate = openshift.process("-f",
                            "${templateDir}/export.cj.json",
                            "ENV_NAME=${prodSuffix}",
                            "PROJECT=${prodProject}",
                            "TAG=${prodSuffix}",
                            "NAME=export-databc",
                            "COMMAND=export_databc",
                            "SCHEDULE='0 5 * * *'"
                        )
                        openshift.apply(exportDataBCCronTemplate).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        def docBackupCronJob = openshift.process("-f",
                            "${templateDir}/jobs/minio-backup/minio-backup.cj.yaml",
                            "NAME_SUFFIX=${prodSuffix}",
                            "NAMESPACE=${prodProject}",
                            "VERSION=v1.0.0",
                            "SCHEDULE='15 4 * * *'",
                            "DEST_PVC=${nfsProdBackupPVC}",
                            "SOURCE_PVC=${minioDataPVC}",
                            "PVC_SIZE=40Gi"
                        )

                        openshift.apply(docBackupCronJob)

                        def dbNFSBackup = openshift.process("-f",
                            "${templateDir}/jobs/postgres-backup-nfs/postgres-backup.cj.yaml",
                            "NAMESPACE=${prodProject}",
                            "TAG_NAME=v12.0.0",
                            "TARGET=gwells-pg12-production",
                            "PVC_NAME=${nfsProdBackupPVC}",
                            "MONTHLY_BACKUPS=12",
                            "SCHEDULE='30 1 * * *'",
                            "JOB_NAME=postgres-nfs-backup"
                        )
                        openshift.apply(dbNFSBackup)

                        // Create cronjob for licence import
                        def importLicencesCronjob = openshift.process("-f",
                            "${templateDir}/jobs/import-licences/import-licences.cj.json",
                            "ENV_NAME=${prodSuffix}",
                            "PROJECT=${prodProject}",
                            "TAG=${prodSuffix}",
                            "NAME=licences",
                            "COMMAND=import_licences",
                            "SCHEDULE='45 11 * * *'"
                        )
                        openshift.apply(importLicencesCronjob).label(
                            [
                                'app':"gwells-${prodSuffix}",
                                'app-name':"${appName}",
                                'env-name':"${prodSuffix}"
                            ],
                            "--overwrite"
                        )

                        // monitor the deployment status and wait until deployment is successful
                        echo "Waiting for deployment to production..."
                        def newVersion = openshift.selector("dc", "gwells-${prodSuffix}").object().status.latestVersion
                        def pods = openshift.selector('pod', [deployment: "gwells-${prodSuffix}-${newVersion}"])

                        // wait until pods reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }

                        def pgtileservVersion = openshift.selector("dc", "pgtileserv-${prodSuffix}").object().status.latestVersion
                        def pgtileservPods = openshift.selector('pod', [deployment: "pgtileserv-${prodSuffix}-${newVersion}"])

                        // wait until each container in this deployment's pod reports as ready
                        timeout(15) {
                            pods.untilEach(2) {
                                return it.object().status.containerStatuses.every {
                                    it.ready
                                }
                            }
                        }

                        createDeploymentStatus(prodSuffix, 'SUCCESS', prodHost)
                    }
                }
            }
        }
    }
}
