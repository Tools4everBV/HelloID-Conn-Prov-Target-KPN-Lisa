#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################

#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $RestMethod = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        $Response = Invoke-RestMethod @RestMethod

        Write-Output $Response.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $httpError = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpError.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpError.ErrorMessage = [System.IO.StreamReader]::new(
                $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpError
    }
}


function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region Aliasses
$Config = $actionContext.Configuration
$Account = $outputContext.Data
$AuditLogs = $outputContext.AuditLogs

$Person = $PersonContext.Person
$Manager = $PersonContext.Manager
#endregion Aliasses

# Start Script
try {
    # TODO:: stukje beunen voor required fields, met harde error als hier niet aan voldaan wordt

    Write-Verbose -Verbose "Getting accessToken"

    $SplatParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }
    $accessToken = Get-LisaAccessToken @SplatParams

    $authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $authorizationHeaders.Add("Authorization", "Bearer $($accessToken)")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    #region Correlation
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ($null -eq $correlationField -or $null -eq $correlationValue) {
            Write-Warning "Correlation is enabled but not configured correctly."
        }

        #  Write logic here that checks if the account can be correlated in the target system
        $SplatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Headers = $authorizationHeaders
            Method  = 'Get'
            Body    = @{
                filter = "$($correlationField)+eq+'$($correlationValue)'"
            }
        }
        $correlatedAccount = Invoke-RestMethod @SplatParams

        if ($correlatedAccount.count -gt 1) {
            throw "Multiple accounts found with filter: $($SplatParams.Body.filter)"
        }

        if ($correlatedAccount.count -eq 1) {
            $correlatedAccount = $correlatedAccount.value

            $outputContext.AccountReference = $correlatedAccount.id

            $Account.PSObject.Properties | ForEach-Object {
                if ($correlatedAccount.PSobject.Properties.Name.Contains($_.Name)) {
                    $Account.$($_.Name) = $correlatedAccount.$($_.Name)
                }
            }

            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated account with username $($correlatedAccount.UserName) on field $($correlationField) with value $($correlationValue)"
                    IsError = $False
                })

            $outputContext.Success = $True
            $outputContext.AccountCorrelated = $True
        }
    }
    #endregion correlation

    # Create KPN Lisa Account
    if (-Not $outputContext.AccountCorrelated) {

        Write-Verbose -Verbose "Creating KPN Lisa account for '$($Person.DisplayName)'"

        if ($Account.PSobject.Properties.Name.Contains("mail") -and $null -eq $Account.mail) {
            $Account.mail = $Account.userPrincipalName
        }

        $Body = $Account | Select-Object @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName'
        )

        $SplatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Headers = $authorizationHeaders
            Method  = 'Post'
            Body    = $Body | ConvertTo-Json
        }

        if (-Not ($actionContext.DryRun -eq $True)) {
            $userResponse = Invoke-RestMethod @SplatParams

            $outputContext.AccountReference = $userResponse.objectId
            $Account | Add-Member -NotePropertyName 'password' -NotePropertyValue $userResponse.temporaryPassword
        }
        else {
            Write-Verbose -Verbose (
                $SplatParams.Body
            )

            $Account | Add-Member -NotePropertyName 'password' -NotePropertyValue "FakePassword"
        }

        #Update the user with all other props
        $Body = $Account | Select-Object -Property *, 'accountEnabled' -ExcludeProperty @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName',
            'password'
        )

        # Force the account disabled
        $body.accountEnabled = $False

        $SplatParams = @{
            Uri     = "$($config.BaseUrl)/Users/$($outputContext.AccountReference)/bulk"
            Headers = $authorizationHeaders
            Method  = 'Patch'
            Body    = $Body | ConvertTo-Json
        }

        if (-not($actionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @SplatParams)
        }
        else {
            Write-Verbose -Verbose (
                $SplatParams.Body
            )
        }

        # Set the manager
        if ($PersonContext.References.ManagerAccount) {
            $SplatParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($outputContext.AccountReference)/Manager"
                Headers = $authorizationHeaders
                Method  = 'Put'
                Body    = $PersonContext.References.ManagerAccount
            }

            if (-not($actionContext.DryRun -eq $True)) {
                [void] (Invoke-RestMethod @SplatParams)
            }

            Write-Verbose -Verbose "Added Manager $($Manager.displayName) to '$($Person.DisplayName)'"
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($Person.DisplayName)'. Id: $($outputContext.AccountReference)"
                IsError = $False
            })

        $outputContext.Success = $True
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose -Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($Person.DisplayName)]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
        })
}
