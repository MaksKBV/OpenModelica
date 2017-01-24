/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE
 * OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3, ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */
/*
 * @author Volker Waurich <volker.waurich@tu-dresden.de>
 */

#ifndef ABSTRACTANIMATIONWINDOW_H
#define ABSTRACTANIMATIONWINDOW_H

#include <QMainWindow>
#include <QToolBar>
#include <QSlider>
#include <QLineEdit>
#include <QComboBox>
#include <QTimer>

#include "FMUSettingsDialog.h"

class VisualizerAbstract;
class ViewerWidget;
class Label;

class AbstractAnimationWindow : public QMainWindow
{
  Q_OBJECT
public:
  AbstractAnimationWindow(QWidget *pParent);
  void openAnimationFile(QString fileName);
  virtual void createActions();
  void clearView();
private:
  bool loadVisualization();
protected:
  //to be animated
  std::string mPathName;
  std::string mFileName;
  //stores the data for the shapes, time management, functionality for updating the values(mat/fmu) etc.
  VisualizerAbstract* mpVisualizer;
  //widgets
  ViewerWidget *mpViewerWidget;
  QToolBar* mpAnimationToolBar;
  QAction *mpAnimationChooseFileAction;
  QAction *mpAnimationInitializeAction;
  QAction *mpAnimationPlayAction;
  QAction *mpAnimationPauseAction;
  QSlider* mpAnimationSlider;
  Label *mpAnimationTimeLabel;
  QLineEdit *mpTimeTextBox;
  Label *mpAnimationSpeedLabel;
  QComboBox *mpSpeedComboBox;
  QComboBox *mpPerspectiveDropDownBox;
  QAction *mpRotateCameraLeftAction;
  QAction *mpRotateCameraRightAction;

  void resetCamera();
  void cameraPositionIsometric();
  void cameraPositionSide();
  void cameraPositionFront();
  void cameraPositionTop();
  double computeDistanceToOrigin();
  void openFMUSettingsDialog(VisualizerFMU *pVisualizerFMU);
public slots:
  void updateScene();
  void chooseAnimationFileSlotFunction();
  void initSlotFunction();
  void playSlotFunction();
  void pauseSlotFunction();
  void sliderSetTimeSlotFunction(int value);
  void jumpToTimeSlotFunction();
  void setSpeedSlotFunction();
  void setPerspective(int value);
  void rotateCameraLeft();
  void rotateCameraRight();
};

#endif // ABSTRACTANIMATIONWINDOW_H
