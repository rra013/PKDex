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

#include <Core/Util/Translator.hpp>
#include <Core/Util/Utilities.hpp>
#include <Core/Gen3/Generators/WildGenerator3.hpp>
#include <Core/Gen3/Searchers/WildSearcher3.hpp>
#include <Core/Gen3/EncounterArea3.hpp>
#include <Core/Gen4/Generators/WildGenerator4.hpp>
#include <Core/Gen4/Searchers/WildSearcher4.hpp>
#include <Core/Gen4/EncounterArea4.hpp>
#include <Core/Gen4/States/WildState4.hpp>
#include <Core/Parents/States/WildState.hpp>
#include <Core/Enum/Encounter.hpp>

#include <Core/Gen3/Generators/EggGenerator3.hpp>
#include <Core/Gen4/Generators/EggGenerator4.hpp>
#include <Core/Gen3/Generators/IDGenerator3.hpp>
#include <Core/Gen4/Generators/IDGenerator4.hpp>
#include <Core/Parents/Daycare.hpp>
#include <Core/Parents/States/EggState.hpp>
#include <Core/Gen3/States/EggState3.hpp>
#include <Core/Gen4/States/EggState4.hpp>
#include <Core/Parents/States/IDState.hpp>
#include <Core/Gen4/States/IDState4.hpp>
#include <Core/Parents/Filters/IDFilter.hpp>

#include <Core/Gen3/Generators/GameCubeGenerator.hpp>
#include <Core/Gen3/ShadowTemplate.hpp>
#include <Core/Enum/ShadowType.hpp>

#include <vector>
#include <cstring>
#include <thread>
#include <variant>

// MARK: - Async Search Handle

struct PFAsyncSearch {
    std::variant<WildSearcher3 *, WildSearcher4 *> searcher;
    std::thread thread;
    bool isGen4;

    ~PFAsyncSearch() {
        if (thread.joinable()) thread.join();
        if (isGen4) delete std::get<WildSearcher4 *>(searcher);
        else delete std::get<WildSearcher3 *>(searcher);
    }
};

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

    // All-false means "no filter" in Swift convention; normalize to all-true
    // so PokeFinder's per-element checks (!natures[i]) don't reject everything
    bool anyNature = false;
    for (int i = 0; i < 25; i++) { if (natArr[i]) { anyNature = true; break; } }
    if (!anyNature) natArr.fill(true);

    bool anyPower = false;
    for (int i = 0; i < 16; i++) { if (powArr[i]) { anyPower = true; break; } }
    if (!anyPower) powArr.fill(true);

    // skip only when genuinely nothing is filtered
    bool allNatures = true;
    for (int i = 0; i < 25; i++) { if (!natArr[i]) { allNatures = false; break; } }
    bool allPowers = true;
    for (int i = 0; i < 16; i++) { if (!powArr[i]) { allPowers = false; break; } }
    bool noIVFilter = true;
    for (int i = 0; i < 6; i++) { if (min[i] > 0 || max[i] < 31) { noIVFilter = false; break; } }

    bool skip = (gender == 255 && ability == 255 && shiny == 255
                 && allNatures && allPowers && noIVFilter);
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

static WildStateFilter makeWildFilter(uint8_t gender, uint8_t ability, uint8_t shiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       const bool encounterSlots[12])
{
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    std::array<bool, 25> natArr;
    std::copy(natures, natures + 25, natArr.begin());

    std::array<bool, 16> powArr;
    std::copy(powers, powers + 16, powArr.begin());

    std::array<bool, 12> slotArr;
    std::copy(encounterSlots, encounterSlots + 12, slotArr.begin());

    bool skip = (gender == 255 && ability == 255 && shiny == 255);
    if (skip) {
        for (int i = 0; i < 12; i++) {
            if (!slotArr[i]) { skip = false; break; }
        }
    }
    return WildStateFilter(gender, ability, shiny, 0, 255, 0, 255, skip, min, max, natArr, powArr, slotArr);
}

static PFWildGeneratorState convertWildGenState(const WildGeneratorState &s)
{
    PFWildGeneratorState r;
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
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

static PFWildSearcherState convertWildSearchState(const WildSearcherState &s)
{
    PFWildSearcherState r;
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
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

static PFEncounterArea convertEncounterArea(const EncounterArea &area)
{
    PFEncounterArea r;
    r.location = area.getLocation();
    r.rate = area.getRate();
    r.encounter = static_cast<uint8_t>(area.getEncounter());
    r.slotCount = area.getCount();
    auto &pokemon = area.getPokemon();
    for (int i = 0; i < 12; i++) {
        r.slots[i].specie = pokemon[i].getSpecie();
        r.slots[i].form = pokemon[i].getForm();
        r.slots[i].minLevel = pokemon[i].getMinLevel();
        r.slots[i].maxLevel = pokemon[i].getMaxLevel();
    }
    return r;
}

static EncounterArea3 findEncounterArea3(Encounter encounter, const EncounterSettings3 &settings,
                                          Game version, uint8_t location)
{
    auto areas = Encounters3::getEncounters(encounter, settings, version);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea3(0, 0, Encounter::Grass, {});
}

static EncounterArea4 findEncounterArea4(Encounter encounter, const EncounterSettings4 &settings,
                                          const Profile4 &profile, uint8_t location)
{
    auto areas = Encounters4::getEncounters(encounter, settings, &profile);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea4(0, 0, Encounter::Grass, {});
}

static PFWildGeneratorState4 convertWildGenState4(const WildGeneratorState4 &s)
{
    PFWildGeneratorState4 r;
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
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    r.call = s.getCall();
    r.chatot = s.getChatot();
    return r;
}

static PFWildSearcherState4 convertWildSearchState4(const WildSearcherState4 &s)
{
    PFWildSearcherState4 r;
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
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

// MARK: - Memory Management

extern "C" void pf_freeResults(void *ptr)
{
    free(ptr);
}

extern "C" void pf_freeString(char *str)
{
    free(str);
}

extern "C" void pf_freeStringArray(char **arr, int count)
{
    for (int i = 0; i < count; i++) free(arr[i]);
    free(arr);
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

// MARK: - Translator

extern "C" void pf_initTranslator(const char *locale)
{
    Translator::init(std::string(locale));
}

static char *copyString(const std::string &s)
{
    char *out = static_cast<char *>(malloc(s.size() + 1));
    std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

extern "C" char *pf_getSpecieName(uint16_t specie)
{
    return copyString(Translator::getSpecie(specie));
}

extern "C" char *pf_getAbilityName(uint16_t ability)
{
    return copyString(Translator::getAbility(ability));
}

extern "C" char *pf_getNatureName(uint8_t nature)
{
    return copyString(Translator::getNature(nature));
}

extern "C" char *pf_getHiddenPowerName(uint8_t power)
{
    return copyString(Translator::getHiddenPower(power));
}

extern "C" char *pf_getItemName(uint16_t item)
{
    return copyString(Translator::getItem(item));
}

extern "C" char *pf_getMoveName(uint16_t move)
{
    return copyString(Translator::getMove(move));
}

extern "C" char **pf_getNatureNames(int *outCount)
{
    auto &natures = Translator::getNatures();
    *outCount = static_cast<int>(natures.size());
    auto **out = static_cast<char **>(malloc(sizeof(char *) * natures.size()));
    for (size_t i = 0; i < natures.size(); i++) {
        out[i] = copyString(natures[i]);
    }
    return out;
}

extern "C" char **pf_getHiddenPowerNames(int *outCount)
{
    auto &powers = Translator::getHiddenPowers();
    *outCount = static_cast<int>(powers.size());
    auto **out = static_cast<char **>(malloc(sizeof(char *) * powers.size()));
    for (size_t i = 0; i < powers.size(); i++) {
        out[i] = copyString(powers[i]);
    }
    return out;
}

extern "C" char **pf_getLocationNames(const uint16_t *locationNums, int count, uint32_t game)
{
    std::vector<u16> nums(locationNums, locationNums + count);
    auto names = Translator::getLocations(nums, static_cast<Game>(game));
    auto **out = static_cast<char **>(malloc(sizeof(char *) * names.size()));
    for (size_t i = 0; i < names.size(); i++) {
        out[i] = copyString(names[i]);
    }
    return out;
}

// MARK: - Encounter Data

extern "C" PFEncounterArea *pf_getEncounters3(uint8_t encounter, uint32_t game,
                                                bool feebasTile, int *outCount)
{
    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    auto areas = Encounters3::getEncounters(static_cast<Encounter>(encounter),
                                             settings, static_cast<Game>(game));
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFEncounterArea *pf_getEncounters4(uint8_t encounter, uint32_t game,
                                                uint16_t tid, uint16_t sid,
                                                int time, bool swarm,
                                                uint32_t dual,
                                                uint16_t replacement0, uint16_t replacement1,
                                                bool feebasTile, bool radar,
                                                int radio,
                                                const uint8_t blocks[5],
                                                int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    EncounterSettings4 settings;
    settings.time = time;
    settings.swarm = swarm;

    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = static_cast<Game>(dual);
        settings.dppt.replacement = { replacement0, replacement1 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = radar;
    } else {
        settings.hgss.radio = radio;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = blocks[i];
    }

    auto areas = Encounters4::getEncounters(static_cast<Encounter>(encounter),
                                             settings, &profile);
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters3(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate3 *templates = Encounters3::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters4(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate4 *templates = Encounters4::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
    }
    return out;
}

// MARK: - Wild Generator Gen 3

extern "C" PFWildGeneratorState *pf_wildGenerate3(uint32_t seed,
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
                                                    int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    WildGenerator3 generator(initialAdvances, maxAdvances, offset,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              feebasTile, area, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState *>(malloc(sizeof(PFWildGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState(results[i]);
    }
    return out;
}

// MARK: - Wild Searcher Gen 3

extern "C" PFWildSearcherState *pf_wildSearch3(uint8_t method,
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
                                                 int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    WildSearcher3 searcher(static_cast<Method>(method), static_cast<Lead>(lead),
                            feebasTile, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState *>(malloc(sizeof(PFWildSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState(results[i]);
    }
    return out;
}

// MARK: - Wild Generator Gen 4

extern "C" PFWildGeneratorState4 *pf_wildGenerate4(uint32_t seed,
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
                                                     int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    WildGenerator4 generator(initialAdvances, maxAdvances, offset,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              feebasTile, false, false, 0, area, profile, filter);

    auto results = generator.generate(seed, 0);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState4 *>(malloc(sizeof(PFWildGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState4(results[i]);
    }
    return out;
}

// MARK: - Wild Searcher Gen 4

extern "C" PFWildSearcherState4 *pf_wildSearch4(uint32_t minAdvance, uint32_t maxAdvance,
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
                                                  int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    WildSearcher4 searcher(minAdvance, maxAdvance, minDelay, maxDelay,
                            static_cast<Method>(method), static_cast<Lead>(lead),
                            feebasTile, false, false, 0, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max, 0);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState4 *>(malloc(sizeof(PFWildSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState4(results[i]);
    }
    return out;
}

// MARK: - Async Wild Searcher Gen 3

extern "C" PFSearchHandle pf_wildSearch3_start(uint8_t method, uint8_t lead,
                                                uint16_t tid, uint16_t sid,
                                                uint32_t game, bool deadBattery, bool feebasTile,
                                                uint8_t encounter, uint8_t location,
                                                uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                const bool natures[25], const bool powers[16],
                                                const bool encounterSlots[12])
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    auto *searcher = new WildSearcher3(static_cast<Method>(method), static_cast<Lead>(lead),
                                        feebasTile, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto *handle = new PFAsyncSearch();
    handle->searcher = searcher;
    handle->isGen4 = false;
    handle->thread = std::thread([searcher, min, max]() {
        searcher->startSearch(min, max);
    });

    return static_cast<PFSearchHandle>(handle);
}

// MARK: - Async Wild Searcher Gen 4

extern "C" PFSearchHandle pf_wildSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                                uint32_t minDelay, uint32_t maxDelay,
                                                uint8_t method, uint8_t lead,
                                                uint16_t tid, uint16_t sid,
                                                uint32_t game, bool feebasTile,
                                                uint8_t encounter, uint8_t location,
                                                uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                const bool natures[25], const bool powers[16],
                                                const bool encounterSlots[12])
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    auto *searcher = new WildSearcher4(minAdvance, maxAdvance, minDelay, maxDelay,
                                        static_cast<Method>(method), static_cast<Lead>(lead),
                                        feebasTile, false, false, 0, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto *handle = new PFAsyncSearch();
    handle->searcher = searcher;
    handle->isGen4 = true;
    handle->thread = std::thread([searcher, min, max]() {
        searcher->startSearch(min, max, 0);
    });

    return static_cast<PFSearchHandle>(handle);
}

// MARK: - Async Search Polling

extern "C" int pf_search_progress(PFSearchHandle handle)
{
    auto *h = static_cast<PFAsyncSearch *>(handle);
    if (h->isGen4) return std::get<WildSearcher4 *>(h->searcher)->getProgress();
    return std::get<WildSearcher3 *>(h->searcher)->getProgress();
}

extern "C" PFWildSearcherState *pf_search3_getResults(PFSearchHandle handle, int *outCount)
{
    auto *searcher = std::get<WildSearcher3 *>(static_cast<PFAsyncSearch *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState *>(malloc(sizeof(PFWildSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState(results[i]);
    }
    return out;
}

extern "C" PFWildSearcherState4 *pf_search4_getResults(PFSearchHandle handle, int *outCount)
{
    auto *searcher = std::get<WildSearcher4 *>(static_cast<PFAsyncSearch *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState4 *>(malloc(sizeof(PFWildSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState4(results[i]);
    }
    return out;
}

extern "C" void pf_search_cancel(PFSearchHandle handle)
{
    auto *h = static_cast<PFAsyncSearch *>(handle);
    if (h->isGen4) std::get<WildSearcher4 *>(h->searcher)->cancelSearch();
    else std::get<WildSearcher3 *>(h->searcher)->cancelSearch();
}

extern "C" void pf_search_free(PFSearchHandle handle)
{
    delete static_cast<PFAsyncSearch *>(handle);
}

// MARK: - Egg Generator Gen 3

extern "C" PFEggGeneratorState3 *pf_eggGenerate3(uint32_t seedHeld, uint32_t seedPickup,
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
                                                    int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator3 generator(initialAdvances, maxAdvances, offset,
                             initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                             calibration, minRedraw, maxRedraw,
                             static_cast<Method>(method), compatibility, daycare, profile, filter);

    auto results = generator.generate(seedHeld, seedPickup);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState3 *>(malloc(sizeof(PFEggGeneratorState3) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].redraws = s.getRedraws();
        out[i].pickupAdvances = s.getPickupAdvances();
    }
    return out;
}

// MARK: - Egg Generator Gen 4

extern "C" PFEggGeneratorState4 *pf_eggGenerate4(uint32_t seedHeld, uint32_t seedPickup,
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
                                                    int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator4 generator(initialAdvances, maxAdvances, offset,
                             initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                             daycare, profile, filter);

    auto results = generator.generate(seedHeld, seedPickup);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState4 *>(malloc(sizeof(PFEggGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].pickupAdvances = s.getPickupAdvances();
        out[i].call = s.getCall();
        out[i].chatot = s.getChatot();
    }
    return out;
}

// MARK: - ID Generator Gen 3 (Ruby/Sapphire)

extern "C" PFIDState *pf_idGenerate3_RS(uint16_t seed,
                                          uint32_t initialAdvances, uint32_t maxAdvances,
                                          int *outCount)
{
    IDFilter filter({}, {}, {}, {}, {}, {});
    IDGenerator3 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generateRS(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState *>(malloc(sizeof(PFIDState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - ID Generator Gen 3 (FRLG/Emerald)

extern "C" PFIDState *pf_idGenerate3_FRLGE(uint16_t tid,
                                              uint32_t initialAdvances, uint32_t maxAdvances,
                                              int *outCount)
{
    IDFilter filter({}, {}, {}, {}, {}, {});
    IDGenerator3 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generateFRLGE(tid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState *>(malloc(sizeof(PFIDState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - ID Generator Gen 4

extern "C" PFIDState4 *pf_idGenerate4(uint32_t minDelay, uint32_t maxDelay,
                                        uint16_t year, uint8_t month, uint8_t day,
                                        uint8_t hour, uint8_t minute,
                                        uint16_t targetTID, bool filterTID,
                                        uint16_t targetSID, bool filterSID,
                                        int *outCount)
{
    std::vector<u16> tidFilter;
    std::vector<u16> sidFilter;
    if (filterTID) tidFilter.push_back(targetTID);
    if (filterSID) sidFilter.push_back(targetSID);

    IDFilter filter(tidFilter, sidFilter, {}, {}, {}, {});
    IDGenerator4 generator(minDelay, maxDelay, year, month, day, hour, minute, filter);

    auto results = generator.generate();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState4 *>(malloc(sizeof(PFIDState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        out[i].delay = results[i].getDelay();
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
        out[i].seconds = results[i].getSeconds();
    }
    return out;
}

// MARK: - GameCube Shadow Templates

extern "C" PFShadowTemplateInfo *pf_getShadowTemplates(int *outCount)
{
    int size = 0;
    const ShadowTemplate *templates = Encounters3::getShadowTeams(&size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFShadowTemplateInfo *>(malloc(sizeof(PFShadowTemplateInfo) * size));
    for (int i = 0; i < size; i++) {
        out[i].specie = templates[i].getSpecie();
        out[i].level = templates[i].getLevel();
        out[i].shadowType = static_cast<uint8_t>(templates[i].getType());
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
    }
    return out;
}

// MARK: - GameCube Shadow Generator

extern "C" PFGeneratorState *pf_gamecubeGenerateShadow(uint32_t seed,
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
                                                        int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const ShadowTemplate *tmpl = Encounters3::getShadowTeam(shadowIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeGenerator generator(initialAdvances, maxAdvances, offset, Method::XDColo, unset, profile, filter);
    auto results = generator.generate(seed, tmpl);

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - GameCube Static Generator

extern "C" PFGeneratorState *pf_gamecubeGenerateStatic(uint32_t seed,
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
                                                        int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate3 *tmpl = Encounters3::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeGenerator generator(initialAdvances, maxAdvances, offset, static_cast<Method>(method), false, profile, filter);
    auto results = generator.generate(seed, tmpl);

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - Seed Verification Tools (Gen 4)

extern "C" char *pf_coinFlips(uint32_t seed)
{
    std::string result = Utilities4::coinFlips(seed);
    return copyString(result);
}

extern "C" char *pf_getCalls(uint32_t seed, uint8_t skips)
{
    std::string result = Utilities4::getCalls(seed, skips);
    return copyString(result);
}
