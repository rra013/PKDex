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

// MARK: - Memory Management

void pf_freeResults(void *ptr);

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

#ifdef __cplusplus
}
#endif

#endif /* PFBridge_h */
