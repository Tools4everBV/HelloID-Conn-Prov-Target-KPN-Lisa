#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$personObj = $person | ConvertFrom-Json
$managerObj = [PSCustomObject]@{
    managerExternalId = $personObj.PrimaryManager.ExternalId
}

$success = $false

# Mapping
$account = [PSCustomObject]@{
    givenName                = $personObj.Name.NickName
    surName                  = $personObj.Name.FamilyName
    userPrincipalName        = "$($personObj.ExternalId)"".onmicrosoft.com"
    displayName              = $personObj.DisplayName
    changePasswordNextSignIn = $false
    usageLocation            = 'NL'
}

#Region internal functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $TenantId,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientId,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]
        $Scope
    )

    try {
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/x-www-form-urlencoded")

        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = $Scope
        }

        $splatRestMethodParameters = @{
            Uri     = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token/"
            Method  = 'POST'
            Headers = $headers
            Body    = $body
        }
        Invoke-RestMethod @splatRestMethodParameters
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = @{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            InvocationInfo        = $ErrorObject.InvocationInfo.MyCommand
            TargetObject          = $ErrorObject.TargetObject.RequestUri
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj['ErrorMessage'] = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj['ErrorMessage'] = $errorResponse
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.TargetObject), InvocationCommand: '$($HttpErrorObj.InvocationInfo)"
    }
}
#EndRegion

if (-not($dryRun -eq $true)) {
    try {
        Write-Verbose 'Getting accessToken'
        $splatGetTokenParams = @{
            TenantId     = $config.TenantId
            ClientId     = $config.ClientId
            ClientSecret = $config.ClientSecret
            Scope        = $config.Scope
        }
        $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token
        $authorizationHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $authorizationHeaders.Add("Authorization", "Bearer $accessToken")
        $authorizationHeaders.Add("Content-Type", "application/json")
        $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

        # Create user
        Write-Verbose "Creating KPN Lisa account for '$($personObj.DisplayName)'"
        $splatParams = @{
            Uri     = "$($config.BaseUrl)/Users?filter=startswith(userprincipalname,'$($account.userPrincipalName)')"
            Method  = 'get'
            Headers = $authorizationHeaders
        }
        $userResponse = Invoke-RestMethod @splatParams
        if ($userResponse.count -eq 0) {
            $splatParams = @{
                Uri     = "$($config.BaseUrl)/Users"
                Method  = 'POST'
                Body    = ($account | ConvertTo-Json)
                Headers = $authorizationHeaders
            }
            $userResponse = Invoke-RestMethod @splatParams
            $objectId = $($userResponse.objectId)
            $auditMessage = "Account '$($personObj.DisplayName)' Created. Id: '$objectId"

            #Set Default WorkSpaceProfile
            $workSpaceProfileGuid = "500708ea-b69f-4f6c-83fc-dd5f382c308b" #WorkspaceProfile   "friendlyDisplayName": "Ontzorgd"

            $splatParams = @{
                Uri     = "$($config.BaseUrl)/Users/$objectId/WorkspaceProfiles"
                Method  = 'PUT'
                Headers = $authorizationHeaders
                body    = ($workSpaceProfileGuid | ConvertTo-Json)
            }
            $null = Invoke-RestMethod @splatParams #If 200 it returns a Empty String
            Write-Verbose "Added Workspace profile [Ontzorgd]" -Verbose

        } elseif ( $userResponse.count -eq 1) {
            $userResponse = $userResponse.value
            $objectId = $($userResponse.id)
            $auditMessage = "Account '$($personObj.DisplayName)' Corrolated. Id: '$objectId"
        }

        if ($userResponse) {
            # Set the manager
            if ($managerObj) {
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/Users?filter=startswith(userprincipalname,'$($managerObj.managerExternalId)')"
                    Method  = 'GET'
                    Headers = $authorizationHeaders
                }
                $managerResponse = Invoke-RestMethod @splatParams

                if ($managerResponse.count -eq 1) {
                    $splatParams = @{
                        Uri     = "$($config.BaseUrl)/Users/$($objectId)/Manager"
                        Method  = 'Put'
                        Body    = ($managerResponse.Value.id | ConvertTo-Json)
                        Headers = $authorizationHeaders
                    }
                    $null = Invoke-RestMethod @splatParams
                    Write-Verbose "Added Manager $($managerResponse.Value.displayName) to '$($personObj.DisplayName)'" -Verbose
                } else {
                    throw  "Manager not Found '$($managerObj.managerExternalId)'"
                }
            }
            $success = $true
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $errorMessage"
        } else {
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $($ex.Exception.Message)"
        }
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AccountReference = $objectId
    AuditDetails     = $auditMessage
}

Write-Output $result | ConvertTo-Json -Depth 10
