#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$Config = $Configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$success = $false
$m = [PSCustomObject]@{
    ExternalId = $p.PrimaryManager.ExternalId
}

# Mapping
$account = [PSCustomObject]@{
    givenName                = $p.Name.NickName
    surName                  = $p.Name.FamilyName
    userPrincipalName        = "$($p.ExternalId)@impegno.onmicrosoft.com"
    displayName              = $p.DisplayName
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
        $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
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
    }
    catch {
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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $reader = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream())
            $HttpErrorObj['ErrorMessage'] = $reader.ReadToEnd()
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.TargetObject), InvocationCommand: '$($HttpErrorObj.InvocationInfo)"
    }
}
#EndRegion

if (-not($dryRun -eq $true)) {
    try {
        Write-Verbose 'Getting accessToken'

        $splatGetTokenParams = @{
            TenantId     = $Config.TenantId
            ClientId     = $Config.ClientId
            ClientSecret = $Config.ClientSecret
            Scope        = $Config.Scope
        }

        $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token

        $authorizationHeaders = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
        $authorizationHeaders.Add("Authorization", "Bearer $accessToken")
        $authorizationHeaders.Add("Content-Type", "application/json")
        $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

        Write-Verbose "Updating KPN Lisa account for '$($p.DisplayName)'"

        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$aRef"
            Method  = 'PATCH'
            Headers = $authorizationHeaders
        }

        if ( ($pd.Name.GivenName) -and ($pd.Name.GivenName.Change -eq "Updated") ) {
            $splatParams['Body'] = [PSCustomObject]@{
                propertyName = "givenName"
                value        = $($pd.Name.GivenName.New)
            } | ConvertTo-Json
            $null = Invoke-RestMethod @splatParams
            $success = $true
            $auditMessage = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
        }
        if ( ($pd.Name.FamilyName) -and ($pd.Name.FamilyName.Change -eq "Updated") ) {
            $splatParams['Body'] = [PSCustomObject]@{
                propertyName = "surName"
                value        = $($pd.Name.FamilyName.New)
            } | ConvertTo-Json
            $null = Invoke-RestMethod @splatParams
            $success = $true
            $auditMessage = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
        }
        if ($null -eq $m) {
            $splatDeleteManagerParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$aRef/manager"
                Method  = 'DELETE'
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatDeleteManagerParams
            $success = $true
            $auditMessage = "Manager for '$($p.DisplayName)' deleted. ObjectId: '$($userResponse.objectId)'"
        }
        elseif ( ($pd.PrimaryManager.PersonId) -and ($pd.PrimaryManager.PersonId.Change -eq "Updated") ) {
            $splatUpdateManagerParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($objectId)/Manager"
                Method  = 'PUT'
                Body    = ($pd.PrimaryManager.PersonId.New | ConvertTo-Json)
                Headers = $authorizationHeaders
            }
            $null = Invoke-RestMethod @splatUpdateManagerParams
            $success = $true
            $auditMessage = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
        }
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account for '$($p.DisplayName)' not updated. Error: $errorMessage"
        }
        else {
            $auditMessage = "Account for '$($p.DisplayName)' not updated. Error: $($ex.Exception.Message)"
        }
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AccountReference = $($userResponse.objectId)
    AuditDetails     = $auditMessage
}

Write-Output $result | ConvertTo-Json -Depth 10
