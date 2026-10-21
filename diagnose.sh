#!/usr/bin/env bash
# diagnose.sh - report which Graph endpoints the Cloud Shell token can reach.
# Usage: curl -s https://raw.githubusercontent.com/arieldavenport/m365-assessment-script/<branch>/diagnose.sh | bash

T=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)
python3 - "$T" <<'PY'
import sys, json, base64
p = sys.argv[1].split('.')[1]
p += '=' * (-len(p) % 4)
c = json.loads(base64.urlsafe_b64decode(p))
print('TENANT:', c.get('tid'))
print('USER:  ', c.get('upn') or c.get('unique_name'))
print('APP:   ', c.get('app_displayname'), c.get('appid'))
print('ROLES: ', c.get('wids'))
print('SCOPES:', c.get('scp'))
PY

for u in 'roleManagement/directory/roleAssignments?$expand=principal($select=id,displayName,userPrincipalName,userType,accountEnabled),roleDefinition&$top=999' \
         'roleManagement/directory/roleAssignments?$expand=principal' \
         'roleManagement/directory/roleAssignments?$top=5' \
         'roleManagement/directory/roleDefinitions?$top=5' \
         'directoryRoles?$expand=members' \
         'directoryRoles' \
         'security/secureScores?$top=1' \
         'security/secureScoreControlProfiles?$top=1' \
         'identityProtection/riskyUsers?$top=1'; do
    c=$(curl -s -o /tmp/diag.json -w '%{http_code}' -H "Authorization: Bearer $T" "https://graph.microsoft.com/v1.0/$u")
    n=$(jq -r 'if .value then (.value | length | tostring) + " rows" else "" end' /tmp/diag.json 2>/dev/null)
    m=$(jq -r '.error.message // empty' /tmp/diag.json 2>/dev/null | head -c 160)
    echo "$c  $u  $n $m"
done
rm -f /tmp/diag.json
