#ifndef PFBridge_h
#define PFBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Result Structs

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint16_t sid;
    uint8_t method; // maps to Method enum
} PFIVToPIDResult;

typedef struct {
    uint32_t seed;
    uint8_t ivs[6];
    uint8_t method;
} PFPIDToIVResult;

typedef struct {
    uint16_t originSeed;
    uint32_t advances;
} PFOriginSeed3;

typedef struct {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
} PFDateTime;

typedef struct {
    PFDateTime dateTime;
    uint32_t delay;
} PFSeedTime4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFGeneratorState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t call;
    uint8_t chatot;
} PFGeneratorState4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFSearcherState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFSearcherState4;

// MARK: - Encounter Slot

typedef struct {
    uint16_t specie;
    uint8_t form;
    uint8_t minLevel;
    uint8_t maxLevel;
} PFSlot;

typedef struct {
    uint8_t location;
    uint8_t rate;
    uint8_t encounter;
    uint8_t slotCount;
    PFSlot slots[12];
} PFEncounterArea;

typedef struct {
    uint32_t game;
    uint16_t specie;
    uint8_t form;
    uint8_t shiny;
    uint8_t ability;
    uint8_t gender;
    uint8_t level;
} PFStaticTemplate;

// MARK: - Wild Generator State

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildGeneratorState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildSearcherState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
    uint8_t call;
    uint8_t chatot;
} PFWildGeneratorState4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildSearcherState4;

// MARK: - Async Searcher Handle

typedef void *PFSearchHandle;

PFSearchHandle pf_wildSearch3_start(uint8_t method, uint8_t lead,
                                     uint16_t tid, uint16_t sid,
                                     uint32_t game, bool deadBattery, bool feebasTile,
                                     uint8_t encounter, uint8_t location,
                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                     const bool natures[25], const bool powers[16],
                                     const bool encounterSlots[12]);

PFSearchHandle pf_wildSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                     uint32_t minDelay, uint32_t maxDelay,
                                     uint8_t method, uint8_t lead,
                                     uint16_t tid, uint16_t sid,
                                     uint32_t game, bool feebasTile,
                                     uint8_t encounter, uint8_t location,
                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                     const bool natures[25], const bool powers[16],
                                     const bool encounterSlots[12]);

int pf_search_progress(PFSearchHandle handle);
PFWildSearcherState *pf_search3_getResults(PFSearchHandle handle, int *outCount);
PFWildSearcherState4 *pf_search4_getResults(PFSearchHandle handle, int *outCount);
void pf_search_cancel(PFSearchHandle handle);
void pf_search_free(PFSearchHandle handle);

// MARK: - Memory Management

void pf_freeResults(void *ptr);
void pf_freeString(char *str);
void pf_freeStringArray(char **arr, int count);

// MARK: - Tools

PFIVToPIDResult *pf_ivToPID(uint8_t hp, uint8_t atk, uint8_t def,
                             uint8_t spa, uint8_t spd, uint8_t spe,
                             uint8_t nature, uint16_t tid,
                             int *outCount);

PFPIDToIVResult *pf_pidToIV(uint32_t pid, int *outCount);

PFOriginSeed3 pf_seedToTimeOriginSeed3(uint32_t seed);

PFDateTime *pf_seedToTime3(uint32_t seed, uint16_t year, int *outCount);

PFSeedTime4 *pf_seedToTime4(uint32_t seed, uint16_t year,
                              bool forceSecond, uint8_t forcedSecond,
                              int *outCount);

// MARK: - Gen 3 Generators

PFGeneratorState *pf_staticGenerate3(uint32_t seed,
                                      uint32_t initialAdvances,
                                      uint32_t maxAdvances,
                                      uint32_t offset,
                                      uint8_t method,
                                      uint16_t tid, uint16_t sid,
                                      uint8_t game,
                                      bool deadBattery,
                                      uint8_t gender, uint8_t ability, uint8_t shiny,
                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                      const bool natures[25], const bool powers[16],
                                      int *outCount);

// MARK: - Gen 3 Searchers

PFSearcherState *pf_staticSearch3(uint8_t method,
                                   uint16_t tid, uint16_t sid,
                                   uint8_t game,
                                   bool deadBattery,
                                   uint8_t gender, uint8_t ability, uint8_t shiny,
                                   const uint8_t ivMin[6], const uint8_t ivMax[6],
                                   const bool natures[25], const bool powers[16],
                                   int *outCount);

// MARK: - Gen 4 Generators

PFGeneratorState4 *pf_staticGenerate4(uint32_t seed,
                                       uint32_t initialAdvances,
                                       uint32_t maxAdvances,
                                       uint32_t offset,
                                       uint8_t method,
                                       uint8_t lead,
                                       uint16_t tid, uint16_t sid,
                                       uint8_t game,
                                       uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       int *outCount);

// MARK: - Gen 4 Searchers

PFSearcherState4 *pf_staticSearch4(uint32_t minAdvance, uint32_t maxAdvance,
                                    uint32_t minDelay, uint32_t maxDelay,
                                    uint8_t method,
                                    uint8_t lead,
                                    uint16_t tid, uint16_t sid,
                                    uint8_t game,
                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                    const bool natures[25], const bool powers[16],
                                    int *outCount);

// MARK: - Translator

void pf_initTranslator(const char *locale);
char *pf_getSpecieName(uint16_t specie);
char *pf_getAbilityName(uint16_t ability);
char *pf_getNatureName(uint8_t nature);
char *pf_getHiddenPowerName(uint8_t power);
char *pf_getItemName(uint16_t item);
char *pf_getMoveName(uint16_t move);
char **pf_getNatureNames(int *outCount);
char **pf_getHiddenPowerNames(int *outCount);
char **pf_getLocationNames(const uint16_t *locationNums, int count, uint32_t game);

// MARK: - Encounter Data

PFEncounterArea *pf_getEncounters3(uint8_t encounter, uint32_t game,
                                    bool feebasTile, int *outCount);
PFEncounterArea *pf_getEncounters4(uint8_t encounter, uint32_t game,
                                    uint16_t tid, uint16_t sid,
                                    int time, bool swarm,
                                    uint32_t dual,
                                    uint16_t replacement0, uint16_t replacement1,
                                    bool feebasTile, bool radar,
                                    int radio,
                                    const uint8_t blocks[5],
                                    int *outCount);
PFStaticTemplate *pf_getStaticEncounters3(int type, int *outCount);
PFStaticTemplate *pf_getStaticEncounters4(int type, int *outCount);

// MARK: - Wild Generators

PFWildGeneratorState *pf_wildGenerate3(uint32_t seed,
                                        uint32_t initialAdvances,
                                        uint32_t maxAdvances,
                                        uint32_t offset,
                                        uint8_t method,
                                        uint8_t lead,
                                        uint16_t tid, uint16_t sid,
                                        uint32_t game,
                                        bool deadBattery,
                                        bool feebasTile,
                                        uint8_t encounter,
                                        uint8_t location,
                                        uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                        const uint8_t ivMin[6], const uint8_t ivMax[6],
                                        const bool natures[25], const bool powers[16],
                                        const bool encounterSlots[12],
                                        int *outCount);

PFWildSearcherState *pf_wildSearch3(uint8_t method,
                                     uint8_t lead,
                                     uint16_t tid, uint16_t sid,
                                     uint32_t game,
                                     bool deadBattery,
                                     bool feebasTile,
                                     uint8_t encounter,
                                     uint8_t location,
                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                     const bool natures[25], const bool powers[16],
                                     const bool encounterSlots[12],
                                     int *outCount);

PFWildGeneratorState4 *pf_wildGenerate4(uint32_t seed,
                                         uint32_t initialAdvances,
                                         uint32_t maxAdvances,
                                         uint32_t offset,
                                         uint8_t method,
                                         uint8_t lead,
                                         uint16_t tid, uint16_t sid,
                                         uint32_t game,
                                         bool feebasTile,
                                         uint8_t encounter,
                                         uint8_t location,
                                         uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                         const uint8_t ivMin[6], const uint8_t ivMax[6],
                                         const bool natures[25], const bool powers[16],
                                         const bool encounterSlots[12],
                                         int *outCount);

PFWildSearcherState4 *pf_wildSearch4(uint32_t minAdvance, uint32_t maxAdvance,
                                      uint32_t minDelay, uint32_t maxDelay,
                                      uint8_t method,
                                      uint8_t lead,
                                      uint16_t tid, uint16_t sid,
                                      uint32_t game,
                                      bool feebasTile,
                                      uint8_t encounter,
                                      uint8_t location,
                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                      const bool natures[25], const bool powers[16],
                                      const bool encounterSlots[12],
                                      int *outCount);

// MARK: - Egg Generator State

typedef struct {
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6]; // 0=random, 1=parent A, 2=parent B
    uint8_t redraws;
    uint32_t pickupAdvances;
} PFEggGeneratorState3;

typedef struct {
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6];
    uint32_t pickupAdvances;
    uint8_t call;
    uint8_t chatot;
} PFEggGeneratorState4;

// MARK: - ID Generator State

typedef struct {
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
} PFIDState;

typedef struct {
    uint32_t seed;
    uint32_t delay;
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
    uint8_t seconds;
} PFIDState4;

// MARK: - Egg Generators

PFEggGeneratorState3 *pf_eggGenerate3(uint32_t seedHeld, uint32_t seedPickup,
                                       uint32_t initialAdvances, uint32_t maxAdvances,
                                       uint32_t offset,
                                       uint32_t initialAdvancesPickup, uint32_t maxAdvancesPickup,
                                       uint32_t offsetPickup,
                                       uint8_t calibration, uint8_t minRedraw, uint8_t maxRedraw,
                                       uint8_t method, uint8_t compatibility,
                                       const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                       uint8_t parentAAbility, uint8_t parentBAbility,
                                       uint8_t parentAGender, uint8_t parentBGender,
                                       uint8_t parentAItem, uint8_t parentBItem,
                                       uint8_t parentANature, uint8_t parentBNature,
                                       uint16_t eggSpecie, bool masuda,
                                       uint16_t tid, uint16_t sid,
                                       uint8_t game, bool deadBattery,
                                       uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       int *outCount);

PFEggGeneratorState4 *pf_eggGenerate4(uint32_t seedHeld, uint32_t seedPickup,
                                       uint32_t initialAdvances, uint32_t maxAdvances,
                                       uint32_t offset,
                                       uint32_t initialAdvancesPickup, uint32_t maxAdvancesPickup,
                                       uint32_t offsetPickup,
                                       const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                       uint8_t parentAAbility, uint8_t parentBAbility,
                                       uint8_t parentAGender, uint8_t parentBGender,
                                       uint8_t parentAItem, uint8_t parentBItem,
                                       uint8_t parentANature, uint8_t parentBNature,
                                       uint16_t eggSpecie, bool masuda,
                                       uint16_t tid, uint16_t sid,
                                       uint8_t game,
                                       uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       int *outCount);

// MARK: - ID Generators

PFIDState *pf_idGenerate3_RS(uint16_t seed,
                              uint32_t initialAdvances, uint32_t maxAdvances,
                              int *outCount);

PFIDState *pf_idGenerate3_FRLGE(uint16_t tid,
                                 uint32_t initialAdvances, uint32_t maxAdvances,
                                 int *outCount);

PFIDState4 *pf_idGenerate4(uint32_t minDelay, uint32_t maxDelay,
                             uint16_t year, uint8_t month, uint8_t day,
                             uint8_t hour, uint8_t minute,
                             uint16_t targetTID, bool filterTID,
                             uint16_t targetSID, bool filterSID,
                             int *outCount);

// MARK: - GameCube Shadow Template Info

typedef struct {
    uint16_t specie;
    uint8_t level;
    uint8_t shadowType;
    uint32_t game;
} PFShadowTemplateInfo;

PFShadowTemplateInfo *pf_getShadowTemplates(int *outCount);

// MARK: - GameCube Generator

PFGeneratorState *pf_gamecubeGenerateShadow(uint32_t seed,
                                             uint32_t initialAdvances,
                                             uint32_t maxAdvances,
                                             uint32_t offset,
                                             int shadowIndex,
                                             bool unset,
                                             uint16_t tid, uint16_t sid,
                                             uint32_t game,
                                             uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                             const uint8_t ivMin[6], const uint8_t ivMax[6],
                                             const bool natures[25], const bool powers[16],
                                             int *outCount);

PFGeneratorState *pf_gamecubeGenerateStatic(uint32_t seed,
                                             uint32_t initialAdvances,
                                             uint32_t maxAdvances,
                                             uint32_t offset,
                                             uint8_t method,
                                             int staticType,
                                             int staticIndex,
                                             uint16_t tid, uint16_t sid,
                                             uint32_t game,
                                             uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                             const uint8_t ivMin[6], const uint8_t ivMax[6],
                                             const bool natures[25], const bool powers[16],
                                             int *outCount);

// MARK: - Seed Verification Tools (Gen 4)
char *pf_coinFlips(uint32_t seed);
char *pf_getCalls(uint32_t seed, uint8_t skips);

#ifdef __cplusplus
}
#endif

#endif /* PFBridge_h */
