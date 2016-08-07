
parse_response <- function(fileNameIn, fileNameOut) {
  # fileNameIn <- "response/response.bin"
  # fileNameOut <- "response/inventory.txt"
  
  con <- file(fileNameIn,  "rb")
  raw <- readBin(con, "raw", file.info(fileNameIn)$size)
  close(con)
  
  # v0.30.0
  start_ind <- head(which(raw == c("a2") &  c(raw[(1+1):length(raw)] == c("06"), rep(FALSE, 1))), n=1)
  end_ind <- tail(which(raw == c("a2") &  c(raw[(1+1):length(raw)] == c("06"), rep(FALSE, 1))), n=1) - 1
  
  # v0.29.2
  # start_ind <- head(which(raw == c("a2") 
  #                         & c(raw[(1+1):length(raw)] == c("06"), rep(FALSE, 1))
  #                         & c(raw[(1+2):length(raw)] == c("02"), rep(FALSE, 2))
  #                         & c(raw[(1+3):length(raw)] == c("08"), rep(FALSE, 3))
  #                         & c(raw[(1+4):length(raw)] == c("01"), rep(FALSE, 4))
  # ), n=1) + 5
  
  inventory_raw <- raw[start_ind:end_ind]
  
  con <- file(file.path("response", "inventory.bin"),  "wb")
  writeBin(inventory_raw, con)
  close(con)
  
  # shell will behave differently on Linux/OSX
  shell(paste0("proto\\protoc.exe --decode Holoholo.Rpc.Inventory proto/inventory.proto < response/inventory.bin > ", fileNameOut)) 
# response/inventory.txt")

}

parse_inventory <- function(fileName) {
  # Parse inventory.txt
  # This should be done using Rprotobuf, please compile against protobuf 3 if you can
  # fileName <- "response/inventory.txt"
  
  con <- file(fileName) 
  txt <- readLines(con)
  close(con)
  
  # number of pokemons including eggs
  N <- sum(grepl("Pokemon \\{", txt)) 
  
  # initialising the final dataframe
  # don't worry about types, will be coerced to character anyways
  df <- data.frame(PokemonId = integer(N),
                   Cp = integer(N),
                   Stamina = integer(N),
                   MaxStamina = integer(N),
                   Move1 = integer(N),
                   Move2 = integer(N),
                   HeightM = numeric(N),
                   WeightKg = numeric(N),
                   IndividualAttack = integer(N),
                   IndividualDefense = integer(N),
                   IndividualStamina = integer(N),
                   CpMultiplier = numeric(N),
                   CapturedS2CellId = character(N),
                   CreationTimeMs = integer(N),
                   FromFort = logical(N),
                   Nickname = character(N),
                   AdditionalCpMultiplier = numeric(N),
                   NumUpgrades = numeric(N),
                   PercentagePerfect = numeric(N),
                   stringsAsFactors = FALSE)
  
  i <- 1
  for (current_line in 1:length(txt)) {
    
    if (grepl("Pokemon \\{", txt[current_line])) {
      
      start_ind <- 3
      end_ind <- head(which(grepl("\\}", txt[(current_line):(current_line+35)])), n=1) - 1
      
      stream <- unlist(strsplit(txt[current_line:(current_line+end_ind)], " "))
      
      for (name in names(df)) {
        value <- stream[head(which(grepl(name, stream)), n=1) + 1]
        if (name == "Nickname" 
            && length(value) > 0 
            && stream[head(which(grepl(name, stream)), n=1) + 2] != "") {
          value <- paste(stream[head(which(grepl(name, stream)), n=1) + 1:2], collapse=" ")
        }
        if (length(value) > 0) df[i, name] <- value
      }
      
      df[i, "PercentagePerfect"] <- round((as.numeric(df[i, "IndividualAttack"]) +
                                       as.numeric(df[i, "IndividualDefense"]) +
                                       as.numeric(df[i, "IndividualStamina"])) / 45 * 100, digits=1)
      
      i <- i+1
      
    }
  }
  
  integerColumns <- c("PokemonId", "Cp", "Stamina", "MaxStamina", "Move1", "Move2",
                      "IndividualAttack", "IndividualDefense", "IndividualStamina", "NumUpgrades")
  df[, integerColumns]  <- sapply(df[, integerColumns], as.integer)
  
  numericColumns <- c("HeightM", "WeightKg", "CpMultiplier", "PercentagePerfect", "AdditionalCpMultiplier")
  df[, numericColumns]  <- sapply(df[, numericColumns], as.numeric)
  
  df[, "FromFort"] <- sapply(df[, "FromFort"], as.logical)
  
  df
}

# ------------------------------------------------------------------------------
# Please note: These functions reference objects in the parent environment which
# is not ideal

compute_cp <- function(id, IVA, IVD, IVS, CpM, ACpM=0){
  rawCp <- with(baseStats, 
                (BaseAttack[id] + IVA) * (BaseDefense[id] + IVD)^0.5 
                * (BaseStamina[id] + IVS)^0.5 * (CpM+ACpM)^2 /10
  )
  max(10, floor(rawCp))
}

compute_cp_max <- function(id, CpM, ACpM=0){
  compute_cp(id, 15, 15, 15, CpM, ACpM)
}

compute_cp_min <- function(id, CpM, ACpM=0){
  compute_cp(id, 0, 0, 0, CpM, ACpM)
}

compute_level <- function(CpMultiplier) {
  levels$Level[which.min(abs(levels$CpMultiplier - CpMultiplier))]
}

compute_cpmultiplier <- function(Level) {
  levels$CpMultiplier[Level*2-1]
}

compute_stardust <- function(level) {
  stardust$Stardust[sum(stardust$Level <= level)]
}


compute_dustcost <- function(current_level, target_level) {
  sum(levels$Stardust[levels$Level >= current_level & levels$Level < target_level])
}

compute_candycost <- function(current_level, target_level) {
  sum(levels$Candy[levels$Level >= current_level & levels$Level < target_level])
}

add_max_evolutions <- function(baseStats) {
  baseStats$Evolution <- as.character(baseStats$Evolution)
  
  # convert to integer
  baseStats$EvolutionInt <- strtoi(paste0("0x", baseStats$Evolution))
  
  # patch wrong values
  baseStats$EvolutionInt[129] <- 130
  baseStats$EvolutionInt[133] <- 134
  baseStats$EvolutionInt[138] <- 139
  baseStats$EvolutionInt[140] <- 141
  baseStats$EvolutionInt[147] <- 148
  baseStats$EvolutionInt[148] <- 149
  
  # add max evolution (not very elegant)
  baseStats$MaxEvolutionInt <- NA
  
  for (id in 1:nrow(baseStats)) {
    max_evo <- NA
    next_evo <- baseStats$EvolutionInt[id]
    if (!is.na(next_evo)) {
      max_evo <- next_evo
      next_evo <- baseStats$EvolutionInt[next_evo]
    }
    if (!is.na(next_evo)) {
      max_evo <- next_evo
      next_evo <- baseStats$EvolutionInt[next_evo]
    }
    baseStats$MaxEvolutionInt[id] <- as.integer(max_evo)
  }
  
  baseStats
}

add_best_movesets  <- function(df) {
  df$RankOffense <- NA
  df$RankDefense <- NA
  df$GymOffense <- NA
  df$GymDefense <- NA
  df$PercentileOffense <- NA
  df$PercentileDefense <- NA
  df$TotalRankOffense <- NA
  df$TotalRankDefense <- NA
  
  df$MaxEvolutionId <- as.integer(df$MaxEvolutionId)
  df$MaxEvolutionId[is.na(df$MaxEvolutionId)] <- df$PokemonId[is.na(df$MaxEvolutionId)]
  
  for (row in 1:nrow(df)) {
    id <- which(df$PokemonId[row] == movesets$Pokemon &
                  df$Move1Name[row] == movesets$Basic.Atk &
                  df$Move2Name[row] == movesets$Charge.Atk)
    # print(id)
    if (length(id) > 0) {
      df$RankOffense[row] <- movesets$Offense.Rank[id]
      df$RankDefense[row] <- movesets$Defense.Rank[id]
      df$GymOffense[row] <- movesets$Gym.Offense[id]
      df$GymDefense[row] <- movesets$Gym.Defense[id]
      df$PercentileOffense[row] <- as.numeric(sub("%", "", movesets$Percentile[id]))
      df$PercentileDefense[row] <- as.numeric(sub("%", "", movesets$Percentile.1[id]))
      
      df$TotalRankOffense[row] <- sum(movesets$Gym.Offense >= movesets$Gym.Offense[id])
      df$TotalRankDefense[row] <- sum(movesets$Gym.Defense >= movesets$Gym.Defense[id])
      
    }
  }
  
  # as.numeric(sub("%", "", movesets$Percentile))
  # as.numeric(sub("%", "", movesets$Percentile.1))
  
  df
  
}


