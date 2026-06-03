// Captura de erros globais para exibição na tela
window.onerror = function(message, source, lineno, colno, error) {
    alert("Erro Javascript: " + message + "\nLinha: " + lineno + "\nOrigem: " + source);
    return false;
};

// Configurações Globais de API e Autenticação
let API_BASE_URL = "";
let userPool = null;
let cognitoUser = null;
let idToken = "";
let isConfigured = false;

// ==============================================================================
// 1. Elementos da DOM - Interface Principal
// ==============================================================================
const uploadZone = document.getElementById("upload-zone");
const fileInput = document.getElementById("file-input");
const progressContainer = document.getElementById("progress-container");
const progressBar = document.getElementById("progress-bar");
const progressFileName = document.getElementById("progress-file-name");
const progressFileSize = document.getElementById("progress-file-size");
const progressStatus = document.getElementById("progress-status");
const btnRefresh = document.getElementById("btn-refresh");

const tabButtons = document.querySelectorAll(".tab-btn");
const tabContents = document.querySelectorAll(".tab-content");

const countRaw = document.getElementById("count-raw");
const countImultavel = document.getElementById("count-imultavel");
const tbodyRaw = document.getElementById("tbody-raw");
const tbodyImultavel = document.getElementById("tbody-imultavel");

// Modal de Detalhes de Registro
const complianceModal = document.getElementById("compliance-modal");
const closeModal = document.getElementById("close-modal");
const btnCloseModalFooter = document.getElementById("btn-close-modal-footer");
const btnDownloadCert = document.getElementById("btn-download-cert");
const detailFilename = document.getElementById("detail-filename");
const detailUuid = document.getElementById("detail-uuid");
const detailHash = document.getElementById("detail-hash");
const detailDate = document.getElementById("detail-date");
const detailLockMode = document.getElementById("detail-lock-mode");
const detailLockDate = document.getElementById("detail-lock-date");

// ==============================================================================
// 2. Elementos da DOM - Autenticação & MFA
// ==============================================================================
const authOverlay = document.getElementById("auth-overlay");
const authErrorMsg = document.getElementById("auth-error-msg");

// Seções
const secLogin = document.getElementById("sec-login");
const secRegister = document.getElementById("sec-register");
const secConfirm = document.getElementById("sec-confirm");
const secMfaChallenge = document.getElementById("sec-mfa-challenge");

// Switchees
const switchToRegister = document.getElementById("switch-to-register");
const switchToLogin = document.getElementById("switch-to-login");

// Inputs
const loginEmail = document.getElementById("login-email");
const loginPassword = document.getElementById("login-password");
const regEmail = document.getElementById("reg-email");
const regPassword = document.getElementById("reg-password");
const confirmCode = document.getElementById("confirm-code");
const mfaChallengeCode = document.getElementById("mfa-challenge-code");

// Botões
const btnLogin = document.getElementById("btn-login");
const btnRegister = document.getElementById("btn-register");
const btnConfirmCode = document.getElementById("btn-confirm-code");
const btnSubmitMfa = document.getElementById("btn-submit-mfa");
const btnLogout = document.getElementById("btn-logout");

// Perfil no Header
const userProfileBar = document.getElementById("user-profile-bar");
const headerUserEmail = document.getElementById("header-user-email");

// Modal de Ativação do MFA
const btnSetupMfaTrigger = document.getElementById("btn-setup-mfa-trigger");
const mfaSetupModal = document.getElementById("mfa-setup-modal");
const closeMfaModal = document.getElementById("close-mfa-modal");
const btnCloseMfaModalFooter = document.getElementById("btn-close-mfa-modal-footer");
const mfaSecretKey = document.getElementById("mfa-secret-key");
const btnCopyMfaKey = document.getElementById("btn-copy-mfa-key");
const mfaSetupCode = document.getElementById("mfa-setup-code");
const btnVerifyMfa = document.getElementById("btn-verify-mfa");
const mfaSetupError = document.getElementById("mfa-setup-error");


// ==============================================================================
// 3. Inicialização e Carregamento de Configurações
// ==============================================================================
async function loadConfig() {
    try {
        // Adiciona um parâmetro de tempo para evitar cache do config.json no navegador
        const response = await fetch("config.json?t=" + new Date().getTime());
        if (!response.ok) throw new Error("Config not found");
        const config = await response.json();
        
        API_BASE_URL = config.api_base_url;
        
        // Inicializa o Amazon Cognito User Pool
        const poolData = {
            UserPoolId: config.cognito_user_pool_id,
            ClientId: config.cognito_client_id
        };
        userPool = new AmazonCognitoIdentity.CognitoUserPool(poolData);
        isConfigured = true;
        
        console.log("Configuração carregada. API:", API_BASE_URL, "Cognito:", poolData.UserPoolId);
        
        // Verifica se há um usuário logado em cache
        checkCachedSession();
        
    } catch (err) {
        console.warn("Arquivo config.json não encontrado ou Cognito não provisionado. Aguardando deploy da pipeline.");
        progressStatus.innerText = "Erro: Configuração não encontrada. Execute o deploy Terraform primeiro.";
        progressStatus.style.color = "var(--color-danger)";
        progressContainer.classList.remove("id-hide");
    }
}

// Verifica sessão ativa salva pelo SDK no localStorage
function checkCachedSession() {
    cognitoUser = userPool.getCurrentUser();
    if (cognitoUser != null) {
        cognitoUser.getSession((err, session) => {
            if (err || !session.isValid()) {
                console.log("Sessão expirada ou inválida. Exibindo painel de Login.");
                showAuthPanel("login");
            } else {
                console.log("Sessão válida encontrada.");
                idToken = session.getIdToken().getJwtToken();
                showDashboard(cognitoUser.getUsername());
            }
        });
    } else {
        showAuthPanel("login");
    }
}

// ==============================================================================
// 4. Controle Visual de Telas (Auth vs Dashboard)
// ==============================================================================
function showAuthPanel(section) {
    authOverlay.classList.remove("id-hide");
    userProfileBar.classList.add("id-hide");
    authErrorMsg.classList.add("id-hide");
    
    // Esconde todas as seções
    secLogin.classList.remove("active");
    secRegister.classList.remove("active");
    secConfirm.classList.remove("active");
    secMfaChallenge.classList.remove("active");
    
    // Mostra a seção desejada
    if (section === "login") secLogin.classList.add("active");
    else if (section === "register") secRegister.classList.add("active");
    else if (section === "confirm") secConfirm.classList.add("active");
    else if (section === "mfa-challenge") secMfaChallenge.classList.add("active");
}

function showDashboard(email) {
    authOverlay.classList.add("id-hide");
    userProfileBar.classList.remove("id-hide");
    headerUserEmail.innerText = email;
    
    // Carrega a listagem de arquivos
    loadDashboard();
    
    // Pooling de atualização de 10s
    if (window.dashboardInterval) clearInterval(window.dashboardInterval);
    window.dashboardInterval = setInterval(loadDashboard, 10000);
}

function showAuthError(msg) {
    authErrorMsg.innerText = msg;
    authErrorMsg.classList.remove("id-hide");
}

// ==============================================================================
// 5. Fluxos de Autenticação com Cognito SDK
// ==============================================================================

// Eventos de troca de telas de autenticação
switchToRegister.addEventListener("click", (e) => { e.preventDefault(); showAuthPanel("register"); });
switchToLogin.addEventListener("click", (e) => { e.preventDefault(); showAuthPanel("login"); });

// Fluxo de Cadastro (Sign Up)
btnRegister.addEventListener("click", () => {
    const email = regEmail.value.trim();
    const password = regPassword.value;
    
    if (!email || !password) {
        showAuthError("Preencha todos os campos.");
        return;
    }
    
    const attributeList = [
        new AmazonCognitoIdentity.CognitoUserAttribute({ Name: "email", Value: email })
    ];
    
    userPool.signUp(email, password, attributeList, null, (err, result) => {
        if (err) {
            showAuthError(err.message || JSON.stringify(err));
            return;
        }
        cognitoUser = result.user;
        console.log("Cadastro efetuado com sucesso. Confirmar e-mail:", cognitoUser.getUsername());
        showAuthPanel("confirm");
    });
});

// Fluxo de Confirmação de Código de Cadastro
btnConfirmCode.addEventListener("click", () => {
    const code = confirmCode.value.trim();
    if (!code) {
        showAuthError("Digite o código de verificação.");
        return;
    }
    
    cognitoUser.confirmRegistration(code, true, (err, result) => {
        if (err) {
            showAuthError(err.message || JSON.stringify(err));
            return;
        }
        alert("E-mail verificado com sucesso! Por favor, faça o login.");
        showAuthPanel("login");
    });
});

// Fluxo de Login (Sign In)
btnLogin.addEventListener("click", () => {
    const email = loginEmail.value.trim();
    const password = loginPassword.value;
    authErrorMsg.classList.add("id-hide");
    
    if (!email || !password) {
        showAuthError("Preencha o e-mail e a senha.");
        return;
    }
    
    const authenticationData = { Username: email, Password: password };
    const authenticationDetails = new AmazonCognitoIdentity.AuthenticationDetails(authenticationData);
    
    const userData = { Username: email, Pool: userPool };
    cognitoUser = new AmazonCognitoIdentity.CognitoUser(userData);
    
    cognitoUser.authenticateUser(authenticationDetails, {
        onSuccess: (result) => {
            console.log("Login efetuado com sucesso.");
            idToken = result.getIdToken().getJwtToken();
            showDashboard(email);
        },
        onFailure: (err) => {
            showAuthError(err.message || JSON.stringify(err));
        },
        // Caso o MFA esteja ativo para o usuário
        mfaRequired: (challengeName, challengeParameters) => {
            console.log("MFA Requerido para o login.");
            showAuthPanel("mfa-challenge");
        }
    });
});

// Envio do código MFA durante o Login
btnSubmitMfa.addEventListener("click", () => {
    const code = mfaChallengeCode.value.trim();
    if (!code) {
        showAuthError("Digite o código gerado pelo aplicativo.");
        return;
    }
    
    cognitoUser.sendMFACode(code, {
        onSuccess: (result) => {
            console.log("Login com MFA efetuado com sucesso.");
            idToken = result.getIdToken().getJwtToken();
            showDashboard(cognitoUser.getUsername());
        },
        onFailure: (err) => {
            showAuthError("Código de MFA inválido: " + err.message);
        }
    });
});

// Logout
btnLogout.addEventListener("click", () => {
    if (cognitoUser) {
        cognitoUser.signOut();
    }
    cognitoUser = null;
    idToken = "";
    if (window.dashboardInterval) clearInterval(window.dashboardInterval);
    console.log("Sign out efetuado.");
    showAuthPanel("login");
});

// ==============================================================================
// 6. Fluxo de Ativação de MFA no Perfil (TOTP / Google Authenticator)
// ==============================================================================
btnSetupMfaTrigger.addEventListener("click", () => {
    mfaSetupError.classList.add("id-hide");
    mfaSetupCode.value = "";
    
    // Obtém o token secreto do Cognito para parear com o app
    cognitoUser.associateSoftwareToken({
        associateSecretCode: (secretCode) => {
            mfaSecretKey.innerText = secretCode;
            mfaSetupModal.classList.remove("id-hide");
        },
        onFailure: (err) => {
            alert("Erro ao associar dispositivo MFA: " + err.message);
        }
    });
});

// Copiar chave do MFA para a área de transferência
btnCopyMfaKey.addEventListener("click", () => {
    navigator.clipboard.writeText(mfaSecretKey.innerText);
    alert("Chave copiada!");
});

// Validar código gerado no app do usuário e ativar o MFA no Cognito
btnVerifyMfa.addEventListener("click", () => {
    const code = mfaSetupCode.value.trim();
    if (!code) {
        mfaSetupError.innerText = "Digite o código gerado.";
        mfaSetupError.classList.remove("id-hide");
        return;
    }
    
    cognitoUser.verifySoftwareToken(code, "Aparelho Celular", {
        onSuccess: (result) => {
            // Define o software token MFA como a preferência de autenticação do usuário
            cognitoUser.setUserMfaPreference(null, {
                Preferred: true,
                Enabled: true
            }, (err, prefResult) => {
                if (err) {
                    mfaSetupError.innerText = "Erro ao definir preferência: " + err.message;
                    mfaSetupError.classList.remove("id-hide");
                } else {
                    alert("Segundo fator de autenticação (MFA) habilitado com sucesso!");
                    mfaSetupModal.classList.add("id-hide");
                }
            });
        },
        onFailure: (err) => {
            mfaSetupError.innerText = "Código de ativação inválido: " + err.message;
            mfaSetupError.classList.remove("id-hide");
        }
    });
});

// Fechar modal do MFA
closeMfaModal.addEventListener("click", () => mfaSetupModal.classList.add("id-hide"));
btnCloseMfaModalFooter.addEventListener("click", () => mfaSetupModal.classList.add("id-hide"));

// ==============================================================================
// 7. Chamadas de API Protegidas com JWT (Header Authorization)
// ==============================================================================

// Upload de Arquivo E2E
async function uploadFile(file) {
    progressContainer.classList.remove("id-hide");
    progressFileName.innerText = file.name;
    progressFileSize.innerText = formatBytes(file.size);
    progressBar.style.width = "0%";
    progressStatus.innerText = "Solicitando permissão de upload seguro...";
    progressStatus.style.color = "var(--color-primary)";

    try {
        // Envia o token JWT ID no cabeçalho de Autorização
        const response = await fetch(`${API_BASE_URL}/presigned-url`, {
            method: "POST",
            headers: { 
                "Content-Type": "application/json",
                "Authorization": idToken // JWT Token exigido pelo Authorizer
            },
            body: JSON.stringify({
                action: "upload",
                file_name: file.name,
                file_type: file.type,
                bucket_type: "raw"
            })
        });

        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.error || "Acesso negado ou erro no servidor.");
        }

        const data = await response.json();
        const uploadUrl = data.upload_url;
        
        progressStatus.innerText = "Enviando arquivo diretamente para o S3 Raw...";
        
        // Upload direto para o S3 (PUT com a URL pré-assinada não precisa de JWT pois a URL já é autenticada temporariamente)
        const xhr = new XMLHttpRequest();
        xhr.open("PUT", uploadUrl, true);
        xhr.setRequestHeader("Content-Type", file.type);
        
        xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
                const percentComplete = (e.loaded / e.total) * 100;
                progressBar.style.width = percentComplete + "%";
                progressStatus.innerText = `Enviando: ${Math.round(percentComplete)}%`;
            }
        };

        xhr.onload = async () => {
            if (xhr.status === 200) {
                progressStatus.innerText = "Upload concluído! Disparando processamento na AWS Lambda...";
                progressStatus.style.color = "var(--color-success)";
                fileInput.value = "";
                
                setTimeout(() => {
                    progressContainer.classList.add("id-hide");
                    loadDashboard();
                }, 2000);
            } else {
                showUploadError(`Erro no S3 (HTTP ${xhr.status})`);
            }
        };

        xhr.onerror = () => showUploadError("Erro de conexão na transmissão para o S3.");
        xhr.send(file);

    } catch (err) {
        showUploadError(err.message);
    }
}

function showUploadError(msg) {
    progressStatus.innerText = `Erro: ${msg}`;
    progressStatus.style.color = "var(--color-danger)";
    progressBar.style.backgroundColor = "var(--color-danger)";
}

// Listagem de Arquivos (Dashboard)
async function loadDashboard() {
    if (!isConfigured || !idToken) return;
    
    try {
        const response = await fetch(`${API_BASE_URL}/files`, {
            headers: {
                "Authorization": idToken // JWT Token exigido pelo Authorizer
            }
        });
        
        if (response.status === 401 || response.status === 403) {
            console.warn("Acesso não autorizado. Efetuando logout automático.");
            btnLogout.click();
            return;
        }
        
        if (!response.ok) throw new Error("Erro ao buscar arquivos no S3");
        const data = await response.json();
        
        countRaw.innerText = data.raw_files.length;
        countImultavel.innerText = data.imultavel_files.length;
        
        renderRawTable(data.raw_files);
        renderImultavelTable(data.imultavel_files);
        
    } catch (err) {
        console.error("Erro ao atualizar painel:", err);
    }
}

function renderRawTable(files) {
    if (files.length === 0) {
        tbodyRaw.innerHTML = `<tr class="empty-state"><td colspan="5">Nenhum arquivo na fila temporária.</td></tr>`;
        return;
    }
    
    tbodyRaw.innerHTML = files.map(file => {
        const dataHora = new Date(file.last_modified).toLocaleString('pt-BR');
        return `
            <tr>
                <td class="font-medium"><i class="fa-solid fa-file-pdf text-danger" style="margin-right: 8px;"></i> ${file.key}</td>
                <td>${formatBytes(file.size)}</td>
                <td>${dataHora}</td>
                <td><span class="status-tag waiting"><i class="fa-solid fa-clock-rotate-left"></i> Raw (Na Fila)</span></td>
                <td class="text-right">
                    <button class="btn btn-secondary btn-sm" onclick="downloadFile('${file.key}', 'raw')">
                        <i class="fa-solid fa-download"></i> Baixar
                    </button>
                </td>
            </tr>
        `;
    }).join("");
}

function renderImultavelTable(files) {
    if (files.length === 0) {
        tbodyImultavel.innerHTML = `<tr class="empty-state"><td colspan="5">Nenhum documento arquivado com imutabilidade ainda.</td></tr>`;
        return;
    }
    
    tbodyImultavel.innerHTML = files.map(file => {
        const dataHora = new Date(file.last_modified).toLocaleString('pt-BR');
        const hasLock = file.object_lock && file.object_lock.active;
        
        const lockHtml = hasLock 
            ? `<span class="lock-tag"><i class="fa-solid fa-lock"></i> COMPLIANCE (Ativo)</span>`
            : `<span class="status-tag waiting"><i class="fa-solid fa-lock-open"></i> Sem Trava</span>`;
            
        const rawJson = encodeURIComponent(JSON.stringify(file));
            
        return `
            <tr>
                <td class="font-medium"><i class="fa-solid fa-file-shield text-success" style="margin-right: 8px;"></i> ${file.key}</td>
                <td>${formatBytes(file.size)}</td>
                <td>${dataHora}</td>
                <td>${lockHtml}</td>
                <td class="text-right" style="display: flex; gap: 0.5rem; justify-content: flex-end;">
                    <button class="btn btn-secondary btn-sm" onclick="showComplianceDetails('${rawJson}')">
                        <i class="fa-solid fa-certificate"></i> Certidão
                    </button>
                    <button class="btn btn-primary btn-sm" onclick="downloadFile('${file.key}', 'imutavel')">
                        <i class="fa-solid fa-download"></i> Baixar
                    </button>
                </td>
            </tr>
        `;
    }).join("");
}

// Download Seguro de Arquivo
async function downloadFile(key, bucketType) {
    try {
        const response = await fetch(`${API_BASE_URL}/presigned-url`, {
            method: "POST",
            headers: { 
                "Content-Type": "application/json",
                "Authorization": idToken // JWT Token exigido pelo Authorizer
            },
            body: JSON.stringify({
                action: "download",
                file_name: key,
                bucket_type: bucketType
            })
        });

        if (!response.ok) throw new Error("Erro ao gerar link de download");
        const data = await response.json();
        
        const tempLink = document.createElement("a");
        tempLink.href = data.download_url;
        tempLink.setAttribute("download", key);
        document.body.appendChild(tempLink);
        tempLink.click();
        document.body.removeChild(tempLink);
        
    } catch (err) {
        alert("Erro ao efetuar o download: " + err.message);
    }
}

// Visualização de Modal de Compliance
async function showComplianceDetails(encodedFileJson) {
    const file = JSON.parse(decodeURIComponent(encodedFileJson));
    detailFilename.innerText = file.key;
    
    const hasLock = file.object_lock && file.object_lock.active;
    const keyParts = file.key.split('_');
    const displayUuid = keyParts[1] ? keyParts[1].toUpperCase() : 'N/A';
    
    detailUuid.innerText = displayUuid;
    detailHash.innerText = sha256Mock(file.key);
    detailDate.innerText = new Date(file.last_modified).toLocaleString('pt-BR');
    
    if (hasLock) {
        detailLockMode.innerText = file.object_lock.mode;
        detailLockDate.innerText = new Date(file.object_lock.retain_until).toLocaleString('pt-BR');
    } else {
        detailLockMode.innerText = "NÃO ATIVO";
        detailLockDate.innerText = "N/A (Livre para exclusão)";
    }
    
    btnDownloadCert.onclick = (e) => {
        e.preventDefault();
        downloadFile(file.key, 'imutavel');
    };
    
    complianceModal.classList.remove("id-hide");
}

// Helpers de Utilidades Gerais
function sha256Mock(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = (hash << 5) - hash + char;
        hash = hash & hash;
    }
    const hex = Math.abs(hash).toString(16).padStart(8, '0');
    return `${hex}a98f12b68c92de5f3774b78912efc4d32a9e8f${hex}`.substring(0, 64);
}

function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// ==============================================================================
// 8. Eventos de Inicialização do Dashboard Estático
// ==============================================================================
uploadZone.addEventListener("click", () => fileInput.click());
uploadZone.addEventListener("dragover", (e) => { e.preventDefault(); uploadZone.classList.add("dragover"); });
uploadZone.addEventListener("dragleave", () => uploadZone.classList.remove("dragover"));
uploadZone.addEventListener("drop", (e) => {
    e.preventDefault();
    uploadZone.classList.remove("dragover");
    if (e.dataTransfer.files.length > 0) handleFile(e.dataTransfer.files[0]);
});
fileInput.addEventListener("change", () => {
    if (fileInput.files.length > 0) handleFile(fileInput.files[0]);
});

function handleFile(file) {
    if (!isConfigured) {
        alert("Erro: Aplicação não configurada.");
        return;
    }
    if (!file.name.toLowerCase().endsWith(".pdf")) {
        alert("Formato inválido. Selecione um arquivo PDF.");
        return;
    }
    uploadFile(file);
}

// Abas do dashboard
tabButtons.forEach(btn => {
    btn.addEventListener("click", () => {
        tabButtons.forEach(b => b.classList.remove("active"));
        tabContents.forEach(c => c.classList.remove("active"));
        btn.classList.add("active");
        document.getElementById(btn.getAttribute("data-tab")).classList.add("active");
    });
});

closeModal.addEventListener("click", () => complianceModal.classList.add("id-hide"));
btnCloseModalFooter.addEventListener("click", () => complianceModal.classList.add("id-hide"));
window.addEventListener("click", (e) => {
    if (e.target === complianceModal) complianceModal.classList.add("id-hide");
});

btnRefresh.addEventListener("click", loadDashboard);

// Carregar Configurações na inicialização da página
loadConfig();
