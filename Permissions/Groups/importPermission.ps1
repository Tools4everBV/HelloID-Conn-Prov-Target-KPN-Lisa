#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Groups-Import
# Correlate to permission
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-KPNLisaError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {

            $errorObjectConverted = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.Error) {
                if ($null -ne $errorObjectConverted.Error.Message) {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error.Message

                    if ($null -ne $errorObjectConverted.Error.Code) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Error code: $($errorObjectConverted.Error.Code)"
                    }

                    if ($null -ne $errorObjectConverted.ErrorDetails) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Additional details: $($errorObjectConverted.ErrorDetails | ConvertTo-Json)"
                    }
                }
                else {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error
                }
            }
            else {
                $httpErrorObj.FriendlyMessage = $ErrorObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Convert-StringToBoolean($obj) {
    foreach ($property in $obj.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [string]) {
            try {
                $obj.$($property.Name) = [System.Convert]::ToBoolean($value)
            }
            catch {
                # Handle cases where conversion fails
                $obj.$($property.Name) = $value
            }
        }
    }
    return $obj
}
#endregion functions

try {
    Write-Information 'Starting target permission import for [KPN Lisa Groups]'

    #region Create access token
    $actionMessage = "creating access token"
    
    $createAccessTokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $actionContext.Configuration.EntraIDAppId
        client_secret = $actionContext.Configuration.EntraIDAppSecret
        scope         = $actionContext.Configuration.KPNMWPScope
    }
    
    $createAccessTokenSplatParams = @{
        Uri             = "https://login.microsoftonline.com/$($actionContext.Configuration.EntraIDTenantID)/oauth2/v2.0/token/"
        Headers         = $headers
        Method          = "POST"
        ContentType     = "application/x-www-form-urlencoded"
        UseBasicParsing = $true
        Body            = $createAccessTokenBody
        Verbose         = $false
        ErrorAction     = "Stop"
    }
    
    $createAccessTokenResponse = Invoke-RestMethod @createAccessTokenSplatParams
    
    Write-Verbose "Created access token. Expires in: $($createAccessTokenResponse.expiresIn | ConvertTo-Json)"
    #endregion Create access token
    
    #region Create headers
    $actionMessage = "creating headers"
    
    $headers = @{
        "Accept"          = "application/json"
        "Content-Type"    = "application/json;charset=utf-8"
        "Mwp-Api-Version" = "1.0"
    }
    
    Write-Verbose "Created headers. Result (without Authorization): $($headers | ConvertTo-Json)."

    # Add Authorization after printing splat
    $headers['Authorization'] = "Bearer $($createAccessTokenResponse.access_token)"
    #endregion Create headers

    #region Get Groups
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/groups
    $actionMessage = "querying groups"

    $kpnLisaGroups = [System.Collections.ArrayList]@()
    do {
        $getKPNLisaGroupsSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/groups"
            Method      = "GET"
            Body        = @{
                Top       = 999
                SkipToken = $Null
            }
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getKPNLisaGroupsResponse.'nextLink')) {
            $getKPNLisaGroupsSplatParams.Body.SkipToken = $getKPNLisaGroupsResponse.'nextLink'
        }

        Write-Verbose "SplatParams: $($getKPNLisaGroupsSplatParams | ConvertTo-Json)"

        # Add header after printing splat
        $getKPNLisaGroupsSplatParams['Headers'] = $headers

        $getKPNLisaGroupsResponse = $null
        $getKPNLisaGroupsResponse = Invoke-RestMethod @getKPNLisaGroupsSplatParams

        if ($getKPNLisaGroupsResponse.Value -is [array]) {
            [void]$kpnLisaGroups.AddRange($getKPNLisaGroupsResponse.Value)
        }
        else {
            [void]$kpnLisaGroups.Add($getKPNLisaGroupsResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getKPNLisaGroupsResponse.'nextLink'))

    # Filter out onPremisesSyncEnabled groups as they can only be managed onPremises
    $kpnLisaGroups = $kpnLisaGroups | Where-Object { $_.onPremisesSyncEnabled -ne $true }
    
    # Filter out grouptypes that cannot be managed from Lisa
    $unSupportedGroupTypes = @("SoftwareUpdatePolicy", "MWP_DeviceDeploymentProfile", "MWP_UserWorkspaceProfile")
    $kpnLisaGroups = $kpnLisaGroups | Where-Object { $_.groupType -notin $unSupportedGroupTypes }

    Write-Information "Queried groups. Result count: $(($kpnLisaGroups | Measure-Object).Count)"
    #endregion Get Groups

    #region Get Groupmembers
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/groups/{identifier}/members
    $actionMessage = "querying Kpn Lisa Group Members"
    foreach ($kpnLisaGroup in $kpnLisaGroups) {
        $kpnLisaGroupMembers = [System.Collections.ArrayList]@()

        do {
            $getKPNLisaGroupMembersSplatParams = @{
                Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/groups/$($kpnLisaGroup.id)/members"
                Method      = "GET"
                Body        = @{
                    Top       = 999
                    SkipToken = $Null
                }
                Verbose     = $false
                ErrorAction = "Stop"
            }
            if (-not[string]::IsNullOrEmpty($getKPNLisaGroupMembersResponse.'nextLink')) {
                $getKPNLisaGroupMembersSplatParams.Body.SkipToken = $getKPNLisaGroupMembersResponse.'nextLink'
            }

            Write-Verbose "SplatParams: $($getKPNLisaGroupMembersSplatParams | ConvertTo-Json)"

            # Add header after printing splat
            $getKPNLisaGroupMembersSplatParams['Headers'] = $headers

            $getKPNLisaGroupMembersResponse = $null
            $getKPNLisaGroupMembersResponse = Invoke-RestMethod @getKPNLisaGroupMembersSplatParams
            $getKPNLisaGroupMembersResponseValue = $getKPNLisaGroupMembersResponse.Value | Where-Object { $_.'memberType' -eq "User" }

            if ($getKPNLisaGroupMembersResponseValue -is [array]) {
                [void]$kpnLisaGroupMembers.AddRange($getKPNLisaGroupMembersResponseValue)
            }
            else {
                [void]$kpnLisaGroupMembers.Add($getKPNLisaGroupMembersResponseValue)
            }
        } while (-not[string]::IsNullOrEmpty($getKPNLisaGroupMembersResponse.'nextLink'))
        $numberOfAccounts = $(($kpnLisaGroupMembers | Measure-Object).Count)

        # Make sure the displayname has a value of max 100 char
        if (-not([string]::IsNullOrEmpty($kpnLisaGroup.displayName))) {
            $displayname = $($kpnLisaGroup.displayName).substring(0, [System.Math]::Min(100, $($kpnLisaGroup.displayName).Length))
        }
        else {
            $displayname = $kpnLisaGroup.id
        }
        # Make sure the description has a value of max 100 char
        if (-not([string]::IsNullOrEmpty($kpnLisaGroup.description))) {
            $description = $($kpnLisaGroup.description).substring(0, [System.Math]::Min(100, $($kpnLisaGroup.description).Length))
        }
        else {
            $description = $null
        }

        $permission = @{
            PermissionReference = @{
                Id = $kpnLisaGroup.id
            }       
            Description         = $description
            DisplayName         = $displayName
        }

        # Batch permissions based on the amount of account references, 
        # to make sure the output objects are not above the limit
        $accountsBatchSize = 500
        if ($numberOfAccounts -gt 0) {
            $accountsBatchSize = 500
            $batches = 0..($numberOfAccounts - 1) | Group-Object { [math]::Floor($_ / $accountsBatchSize ) }
            foreach ($batch in $batches) {
                $permission.AccountReferences = [array]($batch.Group | ForEach-Object { @($kpnLisaGroupMembers[$_].id) })
                Write-Output $permission
            }
        }
    }
    Write-Information 'Target permission import for [KPN Lisa Groups] completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-KPNLisaError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    # Required to write an error as uniqueness check doesn't show auditlog
    Write-Error $auditMessage
}