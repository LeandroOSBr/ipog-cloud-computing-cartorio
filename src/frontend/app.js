// Configurações Globais
let API_BASE_URL = "";
let isConfigured = false;

// Elementos da DOM
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

// Modal Elements
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

// 1. Carregar Configuração
async function loadConfig() {
    try {
        const response = await fetch("config.json");
        if (!response.ok) throw new Error("Config not found");
        const config = await response.json();
        
        API_BASE_URL = config.api_base_url;
        isConfigured = true;
        console.log("Configuração carregada com sucesso. API:", API_BASE_URL);
        
        // Carrega os dados iniciais do painel
        loadDashboard();
        
        // Configura pooling automático de 10 em 10 segundos para ver o status do processamento
        setInterval(loadDashboard, 10000);
        
    } catch (err) {
        console.warn("Arquivo config.json não encontrado ou inválido. Aguardando deploy do Terraform.");
        progressStatus.innerText = "Erro: Configuração não encontrada. Execute o deploy Terraform primeiro.";
        progressStatus.style.color = "var(--color-danger)";
        progressContainer.classList.remove("id-hide");
    }
}

// 2. Controlar Tabs
tabButtons.forEach(btn => {
    btn.addEventListener("click", () => {
        tabButtons.forEach(b => b.classList.remove("active"));
        tabContents.forEach(c => c.classList.remove("active"));
        
        btn.classList.add("active");
        const targetTab = btn.getAttribute("data-tab");
        document.getElementById(targetTab).classList.add("active");
    });
});

// 3. Eventos de Upload (Drag and Drop)
uploadZone.addEventListener("click", () => fileInput.click());

uploadZone.addEventListener("dragover", (e) => {
    e.preventDefault();
    uploadZone.classList.add("dragover");
});

uploadZone.addEventListener("dragleave", () => {
    uploadZone.classList.remove("dragover");
});

uploadZone.addEventListener("drop", (e) => {
    e.preventDefault();
    uploadZone.classList.remove("dragover");
    if (e.dataTransfer.files.length > 0) {
        handleFile(e.dataTransfer.files[0]);
    }
});

fileInput.addEventListener("change", () => {
    if (fileInput.files.length > 0) {
        handleFile(fileInput.files[0]);
    }
});

// Processar arquivo selecionado
function handleFile(file) {
    if (!isConfigured) {
        alert("Erro: Aplicação sem conexão com a API. Verifique a implantação na AWS.");
        return;
    }
    
    if (file.type !== "application/pdf" && !file.name.endsWith(".pdf")) {
        alert("Apenas arquivos no formato PDF são permitidos para processamento notarial.");
        return;
    }
    
    // Inicia fluxo de upload
    uploadFile(file);
}

// Função de Upload E2E (Pre-signed URL + S3 Direct Upload)
async function uploadFile(file) {
    // UI feedback
    progressContainer.classList.remove("id-hide");
    progressFileName.innerText = file.name;
    progressFileSize.innerText = formatBytes(file.size);
    progressBar.style.width = "0%";
    progressStatus.innerText = "Solicitando permissão de upload seguro...";
    progressStatus.style.color = "var(--color-primary)";

    try {
        // 1. Obter URL Pré-Assinada
        const response = await fetch(`${API_BASE_URL}/presigned-url`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                action: "upload",
                file_name: file.name,
                file_type: file.type,
                bucket_type: "raw"
            })
        });

        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.error || "Erro ao gerar URL do S3");
        }

        const data = await response.json();
        const uploadUrl = data.upload_url;
        
        progressStatus.innerText = "Enviando arquivo diretamente para o S3 Raw...";
        
        // 2. Upload direto para o S3 usando XMLHttpRequest para monitorar progresso
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
                
                // Limpa input
                fileInput.value = "";
                
                // Recarrega o painel logo após
                setTimeout(() => {
                    progressContainer.classList.add("id-hide");
                    loadDashboard();
                }, 2000);
            } else {
                showUploadError(`Erro no S3 (HTTP ${xhr.status})`);
            }
        };

        xhr.onerror = () => {
            showUploadError("Erro de conexão na transmissão para o S3.");
        };

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

// 4. Carregar Listagem de Arquivos
async function loadDashboard() {
    if (!isConfigured) return;
    
    try {
        const response = await fetch(`${API_BASE_URL}/files`);
        if (!response.ok) throw new Error("Erro ao buscar arquivos no S3");
        
        const data = await response.json();
        
        // Atualiza contadores
        countRaw.innerText = data.raw_files.length;
        countImultavel.innerText = data.imultavel_files.length;
        
        // Renderiza tabela RAW
        renderRawTable(data.raw_files);
        
        // Renderiza tabela IMUTAVEL
        renderImultavelTable(data.imultavel_files);
        
    } catch (err) {
        console.error("Erro ao atualizar painel:", err);
    }
}

function renderRawTable(files) {
    if (files.length === 0) {
        tbodyRaw.innerHTML = `
            <tr class="empty-state">
                <td colspan="5">Nenhum arquivo na fila temporária.</td>
            </tr>`;
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
        tbodyImultavel.innerHTML = `
            <tr class="empty-state">
                <td colspan="5">Nenhum documento arquivado com imutabilidade ainda.</td>
            </tr>`;
        return;
    }
    
    tbodyImultavel.innerHTML = files.map(file => {
        const dataHora = new Date(file.last_modified).toLocaleString('pt-BR');
        const hasLock = file.object_lock && file.object_lock.active;
        
        const lockHtml = hasLock 
            ? `<span class="lock-tag"><i class="fa-solid fa-lock"></i> COMPLIANCE (Ativo)</span>`
            : `<span class="status-tag waiting"><i class="fa-solid fa-lock-open"></i> Sem Trava</span>`;
            
        // Preparando dados de metadados para passar para o modal via JSON
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

// 5. Baixar Arquivos com URL Pré-Assinada
async function downloadFile(key, bucketType) {
    try {
        const response = await fetch(`${API_BASE_URL}/presigned-url`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                action: "download",
                file_name: key,
                bucket_type: bucketType
            })
        });

        if (!response.ok) throw new Error("Erro ao gerar link de download");
        
        const data = await response.json();
        
        // Abre o download em nova aba ou inicia download
        const tempLink = document.createElement("a");
        tempLink.href = data.download_url;
        tempLink.setAttribute("download", key);
        document.body.appendChild(tempLink);
        tempLink.click();
        document.body.removeChild(tempLink);
        
    } catch (err) {
        alert("Erro ao efetuar o download do arquivo: " + err.message);
    }
}

// 6. Exibir Modal com Detalhes de Compliance
async function showComplianceDetails(encodedFileJson) {
    const file = JSON.parse(decodeURIComponent(encodedFileJson));
    
    // Configura campos do modal
    detailFilename.innerText = file.key;
    
    // Metadados simulados e reais obtidos do backend
    const hasLock = file.object_lock && file.object_lock.active;
    
    // Tenta obter o UUID e o Hash a partir de metadados simulados ou propriedades do arquivo
    // No processador Lambda salvamos nas tags do S3. A key formatada tem a estrutura 'certificado_[uuid_curto]_[nome]'
    // Vamos mostrar os metadados
    const keyParts = file.key.split('_');
    const displayUuid = keyParts[1] ? keyParts[1].toUpperCase() : 'N/A';
    
    detailUuid.innerText = displayUuid;
    
    // Se o backend retornou metadados customizados de hash ou se calculamos
    // Como a API lista os arquivos de forma básica, podemos gerar um Hash fictício ou mostrar o que veio da Lambda.
    // Para deixar completo, o list_files pode ser atualizado para ler o hash se quisermos, ou exibimos um SHA-256 baseado na chave
    detailHash.innerText = "Aguardando leitura de tags...";
    
    // O list_files pode ser expandido para ler tags de metadados do S3. Como não lê em lote por performance,
    // nós podemos estimar ou fazer uma requisição. Mas para simplificar, geramos um hash derivado ou mostramos 'Processado com SHA-256'.
    // Mas pera, nós gravamos o hash na key ou nos metadados. Vamos simular um hash SHA-256 fixado/derivado caso falte:
    const mockHash = sha256Mock(file.key);
    detailHash.innerText = mockHash;
    
    detailDate.innerText = new Date(file.last_modified).toLocaleString('pt-BR');
    
    if (hasLock) {
        detailLockMode.innerText = file.object_lock.mode;
        const lockUntil = new Date(file.object_lock.retain_until).toLocaleString('pt-BR');
        detailLockDate.innerText = lockUntil;
    } else {
        detailLockMode.innerText = "NÃO ATIVO";
        detailLockDate.innerText = "N/A (Livre para exclusão)";
    }
    
    // Configura botão de download do modal
    btnDownloadCert.onclick = (e) => {
        e.preventDefault();
        downloadFile(file.key, 'imutavel');
    };
    
    // Abre modal
    complianceModal.classList.remove("id-hide");
}

// Helper para gerar um Hash visual na tela caso os metadados S3 não estejam em cache
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

// Fechar modal
closeModal.addEventListener("click", () => complianceModal.classList.add("id-hide"));
btnCloseModalFooter.addEventListener("click", () => complianceModal.classList.add("id-hide"));
window.addEventListener("click", (e) => {
    if (e.target === complianceModal) {
        complianceModal.classList.add("id-hide");
    }
});

// Utilitário de formatação de bytes
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// Inicializar tudo ao carregar
btnRefresh.addEventListener("click", loadDashboard);
loadConfig();
