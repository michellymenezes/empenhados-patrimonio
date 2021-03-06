read_historico_tse <- function(arquivo_candidatos_1 = "data/consulta_cand_2012_PB.txt", 
                               arquivo_candidatos_2 = "data/consulta_cand_2016_PB.txt",
                               arquivo_bens_1 = "data/bem_candidato_2012_PB.txt", 
                               arquivo_bens_2 = "data/bem_candidato_2016_PB.txt", 
                               cod_cargo = 11){
    #' Cria um data.frame com o histórico de bens dos atuais eleitos a partir 
    #' dos dados das eleições de 2012 e 2016. 
    #' 
    library(dplyr)
    library(stringr)
    source(here::here("code/import_tse_utils.R"))
    
    declaracao_2012 <- importDecalaracao2012(arquivo_bens_1)
    candidatos_2012 <- importCandidatos2012(arquivo_candidatos_1)
    declaracao_2016 <- importDecalaracao2016(arquivo_bens_2)
    candidatos_2016 <- importCandidatos2016(arquivo_candidatos_2)
    
    atuais_eleitos <- candidatos_2016 %>%
        filter(codCargo %in% cod_cargo, codSituacaoEleito %in% c(1, 2, 3)) %>%
        select(
            sequencialCandidato2016 = sequencialCandidato,
            siglaUnidEleitoral,
            descUnidEleitoral,
            nomeCandidato,
            nomeUrnaCandidato,
            siglaPartido,
            codCargo,
            descCargo,
            cpfCandidato,
            descSituacaoEleito
        )
    
    historico_atuais_eleitos <- atuais_eleitos %>%
        left_join(
            candidatos_2012 %>%
                select(
                    sequencialCandidato2012 = sequencialCandidato,
                    cpfCandidato,
                    codCargo2012 = codCargo,
                    descCargo2012 = descCargo,
                    descSituacaoEleito2012 = descSituacaoEleito,
                    codSituacaoEleito2012 = codSituacaoEleito
                ),
            by = c("cpfCandidato")
        )
    
    declaracao_atuais_eleitos2012 <- historico_atuais_eleitos %>% 
      select(sequencialCandidato2012) %>% 
      left_join(declaracao_2012 %>% select(sequencialCandidato, valorBem),
                by = c("sequencialCandidato2012" = "sequencialCandidato")) %>% 
      
      group_by(sequencialCandidato2012) %>% 
      summarise(totalBens2012 = sum(valorBem))
    
    declaracao_atuais_eleitos2016 <- historico_atuais_eleitos %>% 
      select(sequencialCandidato2016) %>% 
      left_join(declaracao_2016 %>% select(sequencialCandidato, valorBem),
                by = c("sequencialCandidato2016" = "sequencialCandidato")) %>% 
      
      group_by(sequencialCandidato2016) %>% 
      summarise(totalBens2016 = sum(valorBem))
    
    historico_bens_atuais_eleitos <- historico_atuais_eleitos %>% 
      left_join(declaracao_atuais_eleitos2012, by = "sequencialCandidato2012") %>% 
      left_join(declaracao_atuais_eleitos2016, "sequencialCandidato2016") %>% 
      filter(codSituacaoEleito2012 != 6 | is.na(codSituacaoEleito2012)) %>% 
      filter(!(cpfCandidato == "34303197491" & codSituacaoEleito2012 == -1))
    # Caso particular de JOSE FERNANDES GORGONHO NETO em 2012 (foi candidato a prefeito em 2012 mas teve sua campanha renunciada)
    # Foi removido as ocorrências de segundo turno também

    historico_bens_atuais_eleitos %>% 
        mutate_at(c("nomeUrnaCandidato", "descUnidEleitoral"), str_to_title) %>% 
        return()
} 


read_tse_uma_uf = function(estado, ano_eleicao1, ano_eleicao2){
    #' Lê e processa dados de uma UF do TSE para criar ganhos de patrimônio 
    #' já agregados. 
    message("Lendo dados: ", estado, ", ", ano_eleicao1, "-", ano_eleicao2)
    cria_nome_tse = function(tipo, ano, estado) {
        prefix = ifelse(tipo == "bem", "bem_candidato_", "consulta_cand_")
        here::here(paste0("data/",
                          prefix,
                          ano,
                          "/",
                          prefix,
                          ano,
                          "_",
                          estado,
                          ".txt")) %>% 
            return()
    }
    
    arquivo_bens_ano1 = cria_nome_tse("bem", ano_eleicao1, estado)
    arquivo_candidatos_ano1 = cria_nome_tse("candidato", ano_eleicao1, estado)
    arquivo_bens_ano2 = cria_nome_tse("bem", ano_eleicao2, estado)
    arquivo_candidatos_ano2 = cria_nome_tse("candidato", ano_eleicao2, estado)
    
    read_historico_tse(
        arquivo_candidatos_ano1, 
        arquivo_candidatos_ano2,
        arquivo_bens_ano1, 
        arquivo_bens_ano2, 
        cod_cargo = c(11:13)) %>% 
        patrimonios_tidy() %>% 
        return()
}


patrimonios_em_wide <- function(historico){
    historico %>%
        filter(!is.na(totalBens2016),
               !is.na(totalBens2012)) %>% # APENAS QUEM DECLAROU EM AMBOS
        mutate(ganho = totalBens2016 - totalBens2012, 
               ganho_relativo = totalBens2016 / totalBens2012) %>% 
        select(
            cpfCandidato,
            nomeCandidato,
            `2012` = totalBens2012,
            `2016` = totalBens2016,
            ganho,
            ganho_relativo,
            nomeUrnaCandidato,
            siglaPartido,
            descUnidEleitoral, 
            descCargo
        ) %>%
        mutate(rank_ganho = row_number(-ganho), 
               rank_ganho_relativo = row_number(-ganho_relativo)) %>% 
        tidyr::gather("ano", "totalBens", 3:4) %>%
        mutate_at(c("ganho", "ganho_relativo"), 
                  funs(if_else(ano == 2016, ., NA_real_))) 
}

patrimonios_em_historico <- function(historico_completo, patrimonios_wide){
    cargos <- historico_completo %>%
        select(cpfCandidato, `2012` = descCargo2012, `2016` = descCargo) %>%
        mutate(`2012` = if_else(is.na(`2012`), "Nada", `2012`)) %>%
        mutate(`2016` = if_else(is.na(`2016`), "Nada", `2016`)) %>%
        tidyr::gather("ano", "cargo", 2:3)
    
    situacoes <- historico_completo %>%
        select(cpfCandidato, `2012` = descSituacaoEleito2012, `2016` = descSituacaoEleito) %>%
        mutate(`2012` = if_else(is.na(`2012`), "Nada", `2012`)) %>%
        mutate(`2016` = if_else(is.na(`2016`), "Nada", `2016`)) %>%
        tidyr::gather("ano", "situacaoEleito", 2:3)
    
    patrimonios_wide %>% 
        left_join(cargos, by = c("cpfCandidato", "ano")) %>% 
        left_join(situacoes, by = c("cpfCandidato", "ano")) %>% 
        mutate(ano = as.numeric(ano))
}


patrimonios_tidy <- function(historico){
    historico %>%
        mutate(
            ganho = totalBens2016 - totalBens2012, 
            ganho_relativo = totalBens2016 / totalBens2012,
            eleicao_1 = 2012, # TODO: generalizar
            eleicao_2 = 2016, 
            UF = "PB"
        ) %>% 
        select(
            nome_urna = nomeUrnaCandidato,
            unidade_eleitoral = descUnidEleitoral, 
            ganho,
            ganho_relativo,
            patrimonio_eleicao_1 = totalBens2012,
            patrimonio_eleicao_2 = totalBens2016,
            sigla_partido = siglaPartido,
            cargo_pleiteado_1 = descCargo2012,
            resultado_1 = descSituacaoEleito2012,
            cargo_pleiteado_2 = descCargo,
            resultado_2 = descSituacaoEleito,
            cpf = cpfCandidato,
            nome_completo = nomeCandidato
        ) 
}
