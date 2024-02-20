#!/usr/bin/env bash

echo 'PROJECT: Project-bipiti-bopity-boop'

mode=$1

# TODO: To complete this, check if if conditions use these env vars in the workflow 
GITVERSION_TAG_PROPERTY_PULL_REQUESTS='.SemVer'
GITVERSION_TAG_PROPERTY_DEFAULT='.SemVer'
GITVERSION_TAG_PROPERTY_DEVELOP='.SemVer'
GITVERSION_TAG_PROPERTY_RELEASE='.SemVer'
GITVERSION_TAG_PROPERTY_HOTFIX='.SemVer'
GITVERSION_TAG_PROPERTY_MAIN='.MajorMinorPatch'
GITVERSION_REPO_TYPE='SINGLE_APP'
GITVERSION_CONFIG_SINGLE_APP='/repo/.cicd/common/.gitversion.yml'
GITVERSION_CONFIG_MONOREPO='/repo/apps/${svc}/.gitversion.yml'
PROD_BRANCH="main"
TEST_BRANCH="dev"

case "${mode}" in

checkout)
    if [ "${GITHUB_EVENT_NAME}" = 'push' ]; then
        DIFF_DEST="${GITHUB_REF_NAME}"
    else
        DIFF_DEST="${GITHUB_HEAD_REF}"
    fi
    git checkout ${DIFF_DEST}
;;

changed)
    if [ "${GITHUB_EVENT_NAME}" = 'push' ]; then
        DIFF_DEST="${GITHUB_REF_NAME}"
        DIFF_SOURCE=$(git rev-parse "${DIFF_DEST}"^1)
    else
        DIFF_DEST="${GITHUB_HEAD_REF}"
        DIFF_SOURCE="${GITHUB_BASE_REF}"
    fi
    # use main as source if current branch is a release branch
    if [ "$(echo "${DIFF_DEST}" | grep -o '^release/')" = "release/" ]; then
        DIFF_SOURCE=${PROD_BRANCH}
    fi
    # use main as source if current branch is a hotfix branch
    if [ "$(echo "${DIFF_DEST}" | grep -o '^hotfix/')" = "hotfix/" ]; then
        DIFF_SOURCE=${PROD_BRANCH}
    fi
    # echo "::set-output name=diff_source::$DIFF_SOURCE"
    echo "diff_source=${DIFF_SOURCE}" >>$GITHUB_OUTPUT
    # echo "::set-output name=diff_dest::$DIFF_DEST"
    echo "diff_dest=${DIFF_DEST}" >>$GITHUB_OUTPUT
    echo "DIFF_SOURCE='$DIFF_SOURCE'"
    echo "DIFF_DEST='$DIFF_DEST'"

    # setting empty outputs otherwise next steps fail during preprocessing stage
    # echo "::set-output name=changed::''"
    echo "changed=" >>$GITHUB_OUTPUT
    # echo "::set-output name=changed_services::''"
    echo "changed_servcies=" >>$GITHUB_OUTPUT

    # service change calculation with diff - ideally use something like 'plz' or 'bazel'
    if [ "${GITVERSION_REPO_TYPE}" = 'SINGLE_APP' ]; then
        # if [ `git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^src/' | sort | uniq` = 'src/' ]; then
        # ! Modify the grep to match the correct folder which one you should not track for version bump
        echo "changed contiion=$(git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -E -v '^(.github/|.vscode/|.husky|.cicd/)' | sort | uniq)"
        if [ "$(git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -E -v '^(.github/|.vscode/|.husky|.cicd/)' | sort | uniq)" ]; then
        changed=true
        else
        changed=false
        fi
        echo "changed='${changed}'"
        # echo "::set-output name=changed::$changed"
        echo "changed=${changed}" >> $GITHUB_OUTPUT
    else
        if [ "$(git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^common/' > /dev/null && echo 'common changed')" = 'common changed' ]; then
        changed_services=`ls -1 apps | xargs -n 1 printf 'apps/%s\n'`
        else
        changed_services=`git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^apps/[a-zA-Z-]*' | sort | uniq`
        fi
        changed_services=$(printf '%s' "$changed_services" | jq --raw-input --slurp '.')
        # echo "::set-output name=changed_services::$changed_services"
        echo "changed_services=${changed_services}" >> $GITHUB_OUTPUT
        echo "changed_services='$(echo "$changed_services" | sed 'N;s/\n/, /g')'"
    fi
;; 

calculate-version)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${GITVERSION_REPO_TYPE}"
    if [ "${GITVERSION_REPO_TYPE}" = 'SINGLE_APP' ]; then
        service_versions_txt=''
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        service_versions_txt='## Version update\n'
        docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "${CONFIG_FILE}"
        gitversion_calc=$(docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "${CONFIG_FILE}")
        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_PULL_REQUESTS"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        service_version=$(echo "${gitversion_calc}" | jq -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        service_versions_txt+="v${service_version}\n"
        else
        service_versions_txt+='### No version update required\n'
        fi
    else
        service_versions_txt='## Impact surface\n'
        changed_services=( $SEMVERYEASY_CHANGED_SERVICES )
        if [ "${#changed_services[@]}" = "0" ]; then
        service_versions_txt+='### No services changed\n'
        else
        service_versions_txt="## Impact surface\n"
        for svc in "${changed_services[@]}"; do
            echo "calculation for ${svc}"
            CONFIG_FILE=${!CONFIG_FILE_VAR//\$svc/$svc}
            docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "/repo/${svc}/.gitversion.yml"
            gitversion_calc=$(docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "/repo/${svc}/.gitversion.yml")
            GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_PULL_REQUESTS"
            GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
            service_version=$(echo "${gitversion_calc}" | jq -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
            service_versions_txt+="- ${svc} - v${service_version}\n"
        done
        fi
    fi
    # fix multiline variables
    # from: https://github.com/actions/create-release/issues/64#issuecomment-638695206
    # PR_NUMBER=$(echo $GITHUB_REF | awk 'BEGIN { FS = "/" } ; { print $3 }')
    # echo "PR_NUMBER='$PR_NUMBER'"
    # echo "GITHUB_REPOSITORY='$GITHUB_REPOSITORY'"
    # echo "GITHUB_TOKEN='$GITHUB_TOKEN'"
    
    PR_BODY=$service_versions_txt
    git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    git config --global user.name 'github-actions'
    echo "$service_versions_txt" > version.txt
    git add version.txt
    git commit -m "Update version.txt"
    git push
    
    # echo "PR_BODY=${PR_BODY}"
    echo "PR_BODY=${PR_BODY}" >> $GITHUB_OUTPUT
;;

update-pr)
    PR_NUMBER=$(echo "$GITHUB_REF" | awk 'BEGIN { FS = "/" } ; { print $3 }')
    echo "PR_NUMBER='$PR_NUMBER'"

    pr_response=$(curl -sL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")
    current_pr_body=$(echo "$pr_response" | jq '.body')
    formatted_body=$(echo "$current_pr_body" | sed -e 'N;s/\n/\\n/g' -e 's/\\r\\n/\\n/g')
    formatted_body="${formatted_body#\"}"  # Remove double quote from the beginning
    formatted_body="${formatted_body%\"}"  # Remove double quote from the end

    tt=$(echo "$SEMVERY_YEASY_PR_BODY" | sed -e 'N;s/\n/\\n/g' -e 's/\\r\\n/\\n/g')
    echo "SEMVERY_YEASY_PR_BODY='$tt'"

    if [[ $formatted_body == *"$tt"* ]]; then
        echo 'Already version updated'
    else
        jq -nc "{\"body\": \"${SEMVERY_YEASY_PR_BODY}${formatted_body}\" }" | \
        curl -sL  -X PATCH -d @- \
            -H "Content-Type: application/vnd.github+json" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER"
    fi
;;

tag)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${GITVERSION_REPO_TYPE}"

    # https://github.com/orgs/community/discussions/26560
    git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    git config --global user.name 'github-actions'
    if [ "${GITVERSION_REPO_TYPE}" = 'SINGLE_APP' ]; then
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "${CONFIG_FILE}"
        gitversion_calc=$(docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "${CONFIG_FILE}")
        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        service_version=$(echo "${gitversion_calc}" | jq -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        if [ "${GITVERSION_TAG_PROPERTY}" != ".MajorMinorPatch" ]; then
            svc_without_prefix='v'
            previous_commit_count=$(git tag -l | grep "^${svc_without_prefix}$(echo "${gitversion_calc}" | jq -r ".MajorMinorPatch")-$(echo "${gitversion_calc}" | jq -r ".PreReleaseLabel")" | grep -o -E '\.[0-9]+$' | grep -o -E '[0-9]+$' | sort -nr | head -1)
            next_commit_count=$((previous_commit_count+1))
            version_without_count=$(echo "${gitversion_calc}" | jq -r "[.MajorMinorPatch,.PreReleaseLabelWithDash] | join(\"\")")
            full_service_version="${version_without_count}.${next_commit_count}"
        else
            full_service_version="${service_version}"
        fi

        git tag -a "v${full_service_version}" -m "v${full_service_version}"
        git push origin "v${full_service_version}"
        echo "TAG_VALUE=v${full_service_version}" >> $GITHUB_OUTPUT
        fi
    else
        for svc in "${SEMVERYEASY_CHANGED_SERVICES[@]}"; do
        echo "calculation for ${svc}"
        CONFIG_FILE=${!CONFIG_FILE_VAR//\$svc/$svc}
        docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "/repo/${svc}/.gitversion.yml"
        gitversion_calc=$(docker run --rm -v "$(pwd):/repo" ${GITVERSION} /repo /config "/repo/${svc}/.gitversion.yml")
        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        service_version=$(echo "${gitversion_calc}" | jq -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        svc_without_prefix="$(echo "${svc}" | sed "s|^apps/||")"
        if [ "${GITVERSION_TAG_PROPERTY}" != ".MajorMinorPatch" ]; then
            previous_commit_count=$(git tag -l | grep "^${svc_without_prefix}/v$(echo "${gitversion_calc}" | jq -r ".MajorMinorPatch")-$(echo "${gitversion_calc}" | jq -r ".PreReleaseLabel")" | grep -o -E '\.[0-9]+$' | grep -o -E '[0-9]+$' | sort -nr | head -1)
            next_commit_count=$((previous_commit_count+1))
            version_without_count=$(echo "${gitversion_calc}" | jq -r "[.MajorMinorPatch,.PreReleaseLabelWithDash] | join(\"\")")
            full_service_version="${version_without_count}.${next_commit_count}"
        else
            full_service_version="${service_version}"
        fi
        git tag -a "${svc_without_prefix}/v${full_service_version}" -m "${svc_without_prefix}/v${full_service_version}"
        git push origin "${svc_without_prefix}/v${full_service_version}"
        echo "TAG_VALUE=${svc_without_prefix}/v${full_service_version}" >> $GITHUB_OUTPUT
        done
    fi
;;

*)
    echo 'Not a valid mode. Exiting...'
    exit 0
;;

esac
