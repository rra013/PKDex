#import "PFBridge.h"

#include <Core/Util/IVToPIDCalculator.hpp>
#include <Core/Gen3/Tools/PIDToIVCalculator.hpp>
#include <Core/Gen3/Tools/SeedToTimeCalculator3.hpp>
#include <Core/Gen4/Tools/SeedToTimeCalculator4.hpp>
#include <Core/Gen3/Generators/StaticGenerator3.hpp>
#include <Core/Gen3/Searchers/StaticSearcher3.hpp>
#include <Core/Gen4/Generators/StaticGenerator4.hpp>
#include <Core/Gen4/Searchers/StaticSearcher4.hpp>
#include <Core/Gen3/Profile3.hpp>
#include <Core/Gen4/Profile4.hpp>
#include <Core/Gen3/StaticTemplate3.hpp>
#include <Core/Gen4/StaticTemplate4.hpp>
#include <Core/Gen3/Encounters3.hpp>
#include <Core/Gen4/Encounters4.hpp>
#include <Core/Parents/Filters/StateFilter.hpp>
#include <Core/Parents/States/State.hpp>
#include <Core/Parents/States/IVToPIDState.hpp>
#include <Core/Gen3/States/PIDToIVState.hpp>
#include <Core/Gen4/States/State4.hpp>
#include <Core/Gen4/SeedTime4.hpp>
#include <Core/Util/DateTime.hpp>
#include <Core/Enum/Method.hpp>
#include <Core/Enum/Lead.hpp>
#include <Core/Enum/Game.hpp>
#include <Core/Enum/Shiny.hpp>

#include <vector>
#include <cstring>

// MARK: - Helpers

static StateFilter makeFilter(uint8_t gender, uint8_t ability, uint8_t shiny,
                               const uint8_t ivMin[6], const uint8_t ivMax[6],
                               const bool natures[25], const bool powers[16])
{
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    std::array<bool, 25> natArr;
    std::copy(natures, natures + 25, natArr.begin());

    std::array<bool, 16> powArr;
    std::copy(powers, powers + 16, powArr.begin());

    bool skip = (gender == 255 && ability == 255 && shiny == 255);
    return StateFilter(gender, ability, shiny, 0, 255, 0, 255, skip, min, max, natArr, powArr);
}

static PFGeneratorState convertGenState(const GeneratorState &s)
{
    PFGeneratorState r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFGeneratorState4 convertGenState4(const GeneratorState4 &s)
{
    PFGeneratorState4 r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.call = s.getCall();
    r.chatot = s.getChatot();
    return r;
}

static PFSearcherState convertSearchState(const SearcherState &s)
{
    PFSearcherState r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFSearcherState4 convertSearchState4(const SearcherState4 &s)
{
    PFSearcherState4 r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFDateTime convertDateTime(const DateTime &dt)
{
    PFDateTime r;
    auto date = dt.getDate();
    auto time = dt.getTime();
    auto parts = date.getParts();
    r.year = parts.year;
    r.month = parts.month;
    r.day = parts.day;
    r.hour = time.hour();
    r.minute = time.minute();
    r.second = time.second();
    return r;
}

// MARK: - Memory Management

extern "C" void pf_freeResults(void *ptr)
{
    free(ptr);
}

// MARK: - IV To PID

extern "C" PFIVToPIDResult *pf_ivToPID(uint8_t hp, uint8_t atk, uint8_t def,
                                         uint8_t spa, uint8_t spd, uint8_t spe,
                                         uint8_t nature, uint16_t tid,
                                         int *outCount)
{
    auto results = IVToPIDCalculator::calculatePIDs(hp, atk, def, spa, spd, spe, nature, tid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIVToPIDResult *>(malloc(sizeof(PFIVToPIDResult) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        out[i].pid = results[i].getPID();
        out[i].sid = results[i].getSID();
        out[i].method = static_cast<uint8_t>(results[i].getMethod());
    }
    return out;
}

// MARK: - PID To IV

extern "C" PFPIDToIVResult *pf_pidToIV(uint32_t pid, int *outCount)
{
    auto results = PIDToIVCalculator::calculateIVs(pid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFPIDToIVResult *>(malloc(sizeof(PFPIDToIVResult) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        auto ivs = results[i].getIVs();
        for (int j = 0; j < 6; j++) out[i].ivs[j] = ivs[j];
        out[i].method = static_cast<uint8_t>(results[i].getMethod());
    }
    return out;
}

// MARK: - Seed To Time Gen 3

extern "C" PFOriginSeed3 pf_seedToTimeOriginSeed3(uint32_t seed)
{
    u32 advances = 0;
    u16 origin = SeedToTimeCalculator3::calculateOriginSeed(seed, advances);
    return { origin, advances };
}

extern "C" PFDateTime *pf_seedToTime3(uint32_t seed, uint16_t year, int *outCount)
{
    auto results = SeedToTimeCalculator3::calculateTimes(seed, year);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFDateTime *>(malloc(sizeof(PFDateTime) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertDateTime(results[i]);
    }
    return out;
}

// MARK: - Seed To Time Gen 4

extern "C" PFSeedTime4 *pf_seedToTime4(uint32_t seed, uint16_t year,
                                          bool forceSecond, uint8_t forcedSecond,
                                          int *outCount)
{
    auto results = SeedToTimeCalculator4::calculateTimes(seed, year, forceSecond, forcedSecond);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSeedTime4 *>(malloc(sizeof(PFSeedTime4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].dateTime = convertDateTime(results[i].getDateTime());
        out[i].delay = results[i].getDelay();
    }
    return out;
}

// MARK: - Gen 3 Static Generator

extern "C" PFGeneratorState *pf_staticGenerate3(uint32_t seed,
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
                                                  int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    StaticTemplate3 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, false);

    StaticGenerator3 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), tmpl, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - Gen 3 Static Searcher

extern "C" PFSearcherState *pf_staticSearch3(uint8_t method,
                                               uint16_t tid, uint16_t sid,
                                               uint8_t game,
                                               bool deadBattery,
                                               uint8_t gender, uint8_t ability, uint8_t shiny,
                                               const uint8_t ivMin[6], const uint8_t ivMax[6],
                                               const bool natures[25], const bool powers[16],
                                               int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    StaticTemplate3 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, false);

    StaticSearcher3 searcher(static_cast<Method>(method), profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max, &tmpl);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState *>(malloc(sizeof(PFSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState(results[i]);
    }
    return out;
}

// MARK: - Gen 4 Static Generator

extern "C" PFGeneratorState4 *pf_staticGenerate4(uint32_t seed,
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
                                                    int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    StaticTemplate4 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, static_cast<Method>(method));

    StaticGenerator4 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), static_cast<Lead>(lead),
                                tmpl, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState4 *>(malloc(sizeof(PFGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState4(results[i]);
    }
    return out;
}

// MARK: - Gen 4 Static Searcher

extern "C" PFSearcherState4 *pf_staticSearch4(uint32_t minAdvance, uint32_t maxAdvance,
                                                uint32_t minDelay, uint32_t maxDelay,
                                                uint8_t method,
                                                uint8_t lead,
                                                uint16_t tid, uint16_t sid,
                                                uint8_t game,
                                                uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                const bool natures[25], const bool powers[16],
                                                int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    StaticTemplate4 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, static_cast<Method>(method));

    StaticSearcher4 searcher(minAdvance, maxAdvance, minDelay, maxDelay,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max, &tmpl);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState4 *>(malloc(sizeof(PFSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState4(results[i]);
    }
    return out;
}
