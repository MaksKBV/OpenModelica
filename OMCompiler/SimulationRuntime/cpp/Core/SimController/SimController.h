#pragma once
/** @addtogroup coreSimcontroller
 *
 *  @{
 */
#include <Core/SimController/SimManager.h>
#include <Core/SimController/ISimController.h>

class SimController : public ISimController,
                      public SimControllerPolicy
{
public:
    SimController(PATH library_path, PATH modelicasystem_path);
    virtual ~SimController();

    virtual weak_ptr<IMixedSystem> LoadSystem(string modelLib,string modelKey);
    virtual weak_ptr<IMixedSystem> LoadModelicaSystem(PATH modelica_path,string modelKey);
      /// Stops the simulation
    virtual void Stop();
    virtual void Start(SimSettings simsettings, string modelKey);
    virtual void Start(SimSettings simsettings, string modelKey, string nls);
    virtual shared_ptr<IMixedSystem> getSystem(string modelname);
    virtual shared_ptr<ISimObjects> getSimObjects();
    virtual void StartReduceDAE(SimSettings simsettings,string modelPath, string modelKey,bool loadMSL, bool loadPackage);

private:
    shared_ptr<Configuration> _config;
    std::map<string, shared_ptr<IMixedSystem> > _systems;

    // for real-time usage (VxWorks and BODAS)
    //removed, has to be released after simulation run, see SimController.Start
    shared_ptr<SimManager> _simMgr;
    shared_ptr<ISimObjects> _sim_objects;
    #ifdef RUNTIME_PROFILING
    std::vector<MeasureTimeData*> *measureTimeFunctionsArray;
    MeasureTimeValues *measuredFunctionStartValues, *measuredFunctionEndValues;
    #endif
    string _modelLib;
    string _modelKey;
};
/** @} */ // end of coreSimcontroller
