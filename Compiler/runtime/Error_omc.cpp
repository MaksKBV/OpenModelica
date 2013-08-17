/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2010, Linköpings University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THIS OSMC PUBLIC
 * LICENSE (OSMC-PL). ANY USE, REPRODUCTION OR DISTRIBUTION OF
 * THIS PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THE OSMC
 * PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköpings University, either from the above address,
 * from the URL: http://www.ida.liu.se/projects/OpenModelica
 * and in the OpenModelica distribution.
 *
 * This program is distributed  WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

extern "C" {


#include "openmodelica.h"
#include "meta_modelica.h"
#include "rml_compatibility.h"
#define ADD_METARECORD_DEFINTIONS static
#include "OpenModelicaBootstrappingHeader.h"
#include "ModelicaUtilities.h"

}

#include "errorext.cpp"

extern "C" {

void Error_addMessage(int errorID, void *msg_type, void *severity, const char* message, modelica_metatype tokenlst)
{
  ErrorMessage::TokenList tokens;
  if (error_on) {
    while(MMC_GETHDR(tokenlst) != MMC_NILHDR) {
      const char* token = MMC_STRINGDATA(MMC_CAR(tokenlst));
      tokens.push_back(string(token));
      tokenlst=MMC_CDR(tokenlst);
    }
    add_message(errorID,
                (ErrorType) (MMC_HDRCTOR(MMC_GETHDR(msg_type))-Error__SYNTAX_3dBOX0),
                (ErrorLevel) (MMC_HDRCTOR(MMC_GETHDR(severity))-Error__ERROR_3dBOX0),
                message,tokens);
  }
}

extern void* Error_getMessages()
{
  return listReverse(ErrorImpl__getMessages());
}

extern const char* Error_printErrorsNoWarning()
{
  std::string res = ErrorImpl__printErrorsNoWarning();
  return MMC_STRINGDATA(mmc_mk_scon(res.c_str()));
}

extern const char* Error_printMessagesStr()
{
  std::string res = ErrorImpl__printMessagesStr();
  return MMC_STRINGDATA(mmc_mk_scon(res.c_str()));
}

extern void Error_addSourceMessage(int _id, void *msg_type, void *severity, int _sline, int _scol, int _eline, int _ecol, int _read_only, const char* _filename, const char* _msg, void* tokenlst)
{
  ErrorMessage::TokenList tokens;
  if (error_on) {
    while(MMC_GETHDR(tokenlst) != MMC_NILHDR) {
      tokens.push_back(string(MMC_STRINGDATA(MMC_CAR(tokenlst))));
      tokenlst=MMC_CDR(tokenlst);
    }
    add_source_message(_id,
                       (ErrorType) (MMC_HDRCTOR(MMC_GETHDR(msg_type))-Error__SYNTAX_3dBOX0),
                       (ErrorLevel) (MMC_HDRCTOR(MMC_GETHDR(severity))-Error__ERROR_3dBOX0),
                       _msg,tokens,_sline,_scol,_eline,_ecol,_read_only,_filename);
  }
}

extern int Error_getNumMessages()
{
  return errorMessageQueue.size();
}

void Error_setShowErrorMessages(int *show)
{
  showErrorMessages = show ? 1 : 0;
}

}
